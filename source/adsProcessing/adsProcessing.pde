int BAUD_RATE = 115200;//230400;//921600;//460800;//921600; //921600 for Teensy2/Teensy3/Leonardo 460800
int gOscHz = 250; //options include 250, 500, 1000, 2000, 4000, 8000, 16000, 32000 Hz - high bandwidth with many channels will exceed USB/Bluetooth bandwidth
int gOscChannels = 2; //number of channels to report
float gGraphTotalTimeSec = 1; //e.g. if 1 then the last 1 second of data is displayed
float tickSpacing = gGraphTotalTimeSec/5; //e.g. if 0.2 then vertical lines once every 200 ms 
int serialPortNumber = 0; //set to 0 for automatic detection
int screenWid = 1000; //width of scrren, in pixels
int screenHt = 600; //height of screen, in pixels
boolean saveAsText = false; //save a text file you can view with excel
boolean offsetTraces = true; //vertically shift different channels to avoid overlap
boolean testSignal = true;
boolean autoScale = true; //adjust vertical scale based on observed signal variability
//************   no need to edit lines below here *******
//this script was derived from  Sofian Audry’s  Poorman's oscilloscope http://accrochages.drone.ws/en/node/90

import processing.serial.*;
import javax.swing.JOptionPane;//For user input dialogs
import java.util.Date; //for date/time used by saveAsText
PrintWriter output; // for file storage used by saveAsText
Serial port;      // Create object from Serial class
int[]  val;              // Data received from the serial port
int cnt; //sample count
int wm1; //screenWidth -1
int[][] values; //data for up to 3 analog channels
int maxResidualBytes = 1024; //maximum bytes left over from previous transmission
int residualBytes = 0; //number of bytes left over from previous transmission
int[]  residualRawData; //array with bytes left over from previous transmission
//float screenScale24bit = float(screenHt-1)/16777215;
int[] channelMin, channelMax, channelIntercept;
float[] channelSlope;
int halfScreenHt = screenHt / 2;
int positionHt = 200; //height of vertical bar shown at leading edge of oscilloscope
long valuesReceived = 0; 
long calibrationFrames = 240; //number of screen refreshes prior to plotting - allows us to estimate sample rate
float lastSamplePlotted = 0;
float pixelsPerSample = 1;
int Margin = 4; //margin in pixels for top and bottom
long startTime;
int kOscMaxChannels = 15;
int[][] lineColorsRGB = { {255,0,0}, {0,255,0}, {0,0,255}, {255,255,0}, {0,255,255}, {255,0,255},
                         {128,0,0}, {0,128,0}, {0,0,128}, {128,128,0}, {0,128,128}, {128,0,128},
                         {64,0,0}, {0,64,0}, {0,0,64} };

//ads1298 and compatible chips receive three types of commands:
// 1 byte SYSTEM/DATA COMMANDS
//   first byte have decimal values 0x02..0x12
//    x02: Wakeup
//    x04: Standby
//    x06: RESET
//    x08: START
//    x0A: STOP
//    x10: RDATAC - continuous mode
//    x11: SDATAC - stop continuous mode
//    x12: RDATA - data by command

// multiple byte REGISTER COMMANDS
//   REGISTER READ first byte is 0x20+register: has decimal 0x20.. 0x3F
//   REGISTER WRITE first byte is 32+register: has decimal 0x40..0x5F returns byte
//    second byte is number of bytes-1 to write: has decimal value 0..0x1F
//    subsequent bytes are the register values

void adc_send_command(char cmd) {
  delay(1);
  port.write(cmd); 
}

void adc_wreg(char reg, char val)
{
  //see pages 40,43 of datasheet - 
  delay(1);
  port.write(0x40 | reg); //0x40 = wreg
  port.write(0);  // number of registers to be read/written – 1
  port.write(val);
}

int adc_rreg(char reg){ //read register
  while (port.available() > 0)  port.read();  
  delay(1);
  port.write(0x20 + reg); //0x20 = rreg
  delay(1);
  port.write(0);  // number of registers to be read/written – 1
  for (int c=0;c<100;c++) //there is often some latency with USB communications
    if (port.available() < 1)
      delay(1);
  if (port.available() < 1) return -1;
  return port.readChar();
}

int adc_rrreg(char reg){ //robust read register
  while (port.available() > 0)  port.read();
  int IDval = -1;
  for (int c=0;c<25;c++) //just in case device is confused with this instruction
    if  (IDval < 0)  IDval = adc_rreg(reg); //read register: Identification 
  return IDval;
}

void ads_getMaxChannels() {
  int nMaxChan = 0;
  int IDval =  adc_rrreg(char (0x00)); //read register: Identification
  switch (IDval  & 31) { //least significant bits reports channels
          case  16://ads1294
            nMaxChan = 4;
            break;
          case 17://ads1296
            nMaxChan = 6;
            break;
          case 18://ads1298
            nMaxChan = 8;//ads1298
            break;
          case 30://ads1299
            nMaxChan = 8;//ads1299
            break;
          //default: 
          //  nMaxChan = 0;
    }
    kOscMaxChannels = nMaxChan;
    if (nMaxChan == 0) {
       print("Error: Unable to detect ADS1298 or similar device. Device register ID returned ");println(IDval);
       exit();
       return;
    }
    if (gOscChannels > nMaxChan) {
       print("Error: connected device can only support ");print(nMaxChan); println(" channels");
       exit();      
      return; 
    }
    print("Channels available: "); print(nMaxChan); print(" Device ID register value: "); println(IDval);     
}

void ads_close() {
  adc_send_command(char(0x11)); //SDATAC - stop data transfer
}

/* minimal script for acquiring data - uses chip default - gOscChannels must equal ads129n channels, e.g. 8 for ads1298
void ads_setupSimple() {
  delay(1);
  while (port.available() > 0)  port.read();
  adc_send_command(char(0x11)); //SDATAC - stop data
  delay(250);
  ads_getMaxChannels();
  adc_send_command(char(0x10)); //RDATAC = start continuous data  
}*/


void ads_setupSimple() {
  char SDATAC = 0x11;
  char RDATAC = 0x10;
  char ID = 0x00;
  char GPIO = 0x14;
  char CONFIG3 = 0x03;
  char RLDREF_INT = 0x08;
  char PD_RLD = 0x04;
  char PD_REFBUF = 0x80;
  char VREF_4V = 0x20;
  char CONFIG3_const = 0x40;
  char RLD_SENSP = 0x0d;
  char RLD_SENSN = 0x0e;
  char CONFIG1 = 0x01;
  char CONFIG2 = 0x02;
  char CHnSET = 0x04;
  char HR = 0x80;
  char DR2 = 0x04;
  char DR1 = 0x02;
  char DR0 = 0x01;
  char HIGH_RES_32k_SPS = char(HR);
  char HIGH_RES_16k_SPS = char(HR | DR0);
  char HIGH_RES_8k_SPS = char(HR | DR1);
  char HIGH_RES_4k_SPS = char(HR | DR1 | DR0);
  char HIGH_RES_2k_SPS = char(HR | DR2);
  char HIGH_RES_1k_SPS = char(HR | DR2 | DR0);
  char HIGH_RES_500_SPS = char(HR | DR2 | DR1);
  //char HIGH_RES_500_SPS = char( DR2 | DR1);
  char HIGH_RES_250_SPS = char(HR |DR2 | DR1);
  char LOW_POWR_250_SPS = char(DR2 | DR1);
  char LOW_POWR_1k_SPS = char(DR2 | DR0);
  char INT_TEST = 0x10;
  char TEST_AMP = 0x00; //double amplitude of test signal to 2 x -(VREFP-VREFN)/2.4mV
  //char TEST_AMP = 0x04; //double amplitude of test signal to 2 x -(VREFP-VREFN)/2.4mV
 
  char TEST_FREQ1 = 0x02; 
  char TEST_FREQ0 = 0x01; 
  char INT_TEST_4HZ_AMP = char(INT_TEST | TEST_AMP); //power saving 2Hz , precision 1Hz (0.98)
  char INT_TEST_8HZ_AMP = char(INT_TEST | TEST_FREQ0 | TEST_AMP);  //power saving 4Hz highres = 2 Hz (1.95)
    
  char GAINn2 = 0x40;
  char GAINn1 = 0x20; 
  char GAIN_12X = char(GAINn2 | GAINn1);
  char PDn = 0x80; //power down amplifier
  char MUXn2 = 0x04;
  char  MUXn1 = 0x02;
  char MUXn0 = 0x01;
  char TEST_SIGNAL = char(MUXn2 | MUXn0);
  char ELECTRODE_INPUT = 0x00;
  char SHORTED = MUXn0;
  adc_send_command(SDATAC);
  delay(250); //a delay is required to allow the device to respond to commands
  //check device
  ads_getMaxChannels();
  // All GPIO set to output 0x0000: (floating CMOS inputs can flicker on and off, creating noise)
  adc_wreg(GPIO, char(0));
  //register CONFIG1 sets sample rate, daisy-chain, resolution (high vs power saving) and CLK connection
  if (gOscHz < 375) 
    adc_wreg(CONFIG1, HIGH_RES_250_SPS);
  else if (gOscHz < 750) 
    adc_wreg(CONFIG1,HIGH_RES_500_SPS);
  else if (gOscHz < 1500) 
    adc_wreg(CONFIG1,HIGH_RES_1k_SPS);
  else if (gOscHz < 3000)
    adc_wreg(CONFIG1,HIGH_RES_2k_SPS);
  else if (gOscHz < 6000)
    adc_wreg(CONFIG1,HIGH_RES_4k_SPS);
  else if (gOscHz < 12000)
    adc_wreg(CONFIG1,HIGH_RES_8k_SPS);
  else if (gOscHz < 24000) 
    adc_wreg(CONFIG1,HIGH_RES_16k_SPS);
  else
    adc_wreg(CONFIG1,HIGH_RES_32k_SPS);   
  //register CONFIG1 sets WCT, internal/external test signal, test amplifier and test frequency
  adc_wreg(CONFIG2, INT_TEST_4HZ_AMP);  // generate internal test signals
  //register CONFIG3 sets multi-reference and RLD operation
  adc_wreg(CONFIG3,char(PD_REFBUF | CONFIG3_const)); //PD_REFBUF used for test signal
  //To use RLD:  Power up the internal reference and wait for it to settle
  // adc_wreg(CONFIG3,char( RLDREF_INT | PD_RLD | PD_REFBUF | VREF_4V | CONFIG3_const));
  // delay(150);
  //You would also specify which channels to use for RLD
  // adc_wreg(RLD_SENSP, char(0x01));  // only use channel IN1P and IN1N
  // adc_wreg(RLD_SENSN, char(0x01));  // for the RLD Measurement

  // Set channels to record 
  if (testSignal) {
    for (int i = 1; i <= gOscChannels; i++) 
      adc_wreg(char(CHnSET + i), char(TEST_SIGNAL | GAIN_12X));
  }  else {
    for (int i = 1; i <= gOscChannels; i++) 
      adc_wreg(char(CHnSET + i), char(ELECTRODE_INPUT | GAIN_12X));
  }
  if (gOscChannels < kOscMaxChannels) {
    for (int i = (gOscChannels+1); i <= kOscMaxChannels; i++)
       adc_wreg(char(CHnSET + i), char(PDn | SHORTED));  //turn off unused amplifiers 
  }
  adc_send_command(RDATAC);  
}

void exit()  { //put the Arduino back into default keyboard mode
    //terminateAll = true;
    ads_close();
    if (saveAsText) {
      output.flush(); // Write the remaining data
      output.close(); //close the text file
    }
    super.exit();
} //exit()

void calibrateFrameRate()
{
  if (valuesReceived < 1) {
    println("Error: No samples detected: either device is not connected or serialPortNumber is wrong.");
    exit();
  }
  float plotEveryNthSample;
  plotEveryNthSample = (gGraphTotalTimeSec/float(screenWid)* float(gOscHz));
  if (plotEveryNthSample > 1) plotEveryNthSample = round(plotEveryNthSample);
  if (plotEveryNthSample == 1) plotEveryNthSample = 1; 
  pixelsPerSample = 1 / plotEveryNthSample;
  float estHz = (1000*valuesReceived)/(millis()-startTime);
  if ((tickSpacing == 0) || (screenWid == 0) || (plotEveryNthSample ==0) || (gOscHz == 0) ) //avoid divide by zero
    tickSpacing = screenWid / 4;
  else {
    tickSpacing = screenWid /  (((screenWid *plotEveryNthSample)/ gOscHz)/tickSpacing);
  }
  print("Requested ");  print(gOscHz); print("Hz, so far we have observed "); print(estHz); println("Hz");
  print ("Displaying  ");  print(pixelsPerSample); print(" pixels per sample, so the screen shows "); print((screenWid *plotEveryNthSample)/ gOscHz); println(" Sec");
} //calibrateFrameRate()

void setPortNum() 
{
   String[] portStr = Serial.list();
   int nPort = portStr.length;
   if (nPort < 1) {
      javax.swing.JOptionPane.showMessageDialog(frame,"No devices detected: please check Arduino power and drivers.");  
      exit();    
   }
   int index = 0;
   for (int i=0; i<nPort; i++) {
     if (match(portStr[i], "cu.us") != null) index = i; //Arduino/Teensy names like /dev/cu.usbmodem*" and our BlueTooth is  /dev/cu.us922k0000bt 
     portStr[i] =  i+ " "+portStr[i] ;
   }  
   String respStr = (String) JOptionPane.showInputDialog(null,
      "Choose your device (if not listed: check drivers and power)", "Select Arduino",
      JOptionPane.PLAIN_MESSAGE, null,
      portStr, portStr[index]);
   serialPortNumber = Integer.parseInt(respStr.substring(0, 1));  
} //setPortNum()

void autoScaleChannel (int ch) {
  int Ht = screenHt-Margin-Margin;
  if (offsetTraces) Ht = Ht - (gOscChannels * 2);
  if ((Ht < 1) || (ch < 0) || (ch >= kOscMaxChannels) || (channelMin[ch] > channelMax[ch])) return;
  if (channelMin[ch] == channelMax[ch]) {
    channelSlope[ch] = 0;
    return; 
  }
  channelSlope[ch] = float(Ht)/ float(channelMax[ch] - channelMin[ch]);
} //autoScaleChannel()


void setup() 
{
  residualRawData = new int[maxResidualBytes];
  //setup vertical scaling
  channelMin= new int[kOscMaxChannels];
  channelMax= new int[kOscMaxChannels];
  channelSlope= new float[kOscMaxChannels];
  channelIntercept= new int[kOscMaxChannels];
  for (int c=0;c<kOscMaxChannels;c++) {
    if (offsetTraces) 
      channelIntercept[c] = Margin+ (c * 2);
    else
      channelIntercept[c] = Margin;
    channelMin[c] = -8388608; //minimum 24-bit signed integer
    channelMax[c] = 8388607; //maximum 24-bit signed integer
    autoScaleChannel(c);
    if (autoScale) { //set impossible values to detect true variability
      channelMin[c] = 8388607;
      channelMax[c] = -8388608;        
    }
  }
  if (gOscChannels > lineColorsRGB.length) {
    println("Error: you need to specify more colors to the array lineColorsRGB.");
    exit();   
  } 
  if (gOscChannels > kOscMaxChannels) {
    print("Error: you requested "); print(gOscChannels); print(" channels but this software currently only supports ");println(kOscMaxChannels);
    exit();   
  } 
  if (serialPortNumber == 0) {
    setPortNum();
  } else {
    print("Will attempt to open port "); println(serialPortNumber); 
    println(", this should correspond to the device number in this list:");
    println(Serial.list());
    println("Hint: if you set serialPortNumber=0 the program will allow the user to select from a drop down list of available ports");
  }
  port = new Serial(this, Serial.list()[serialPortNumber], BAUD_RATE);    
  //hardware check
  while (port.available() > 0)  port.read();
  startTime = 0;
  size(screenWid, screenHt);                                  //currently set to 5 sec
  //serialBytes = new int[packetBytes];
  val = new int[gOscChannels]; //most recent sample for each channel
  values = new int[gOscChannels][width]; //previous samples for each channel
  wm1= width-1; 
  cnt = 1;     
  frameRate(60); //refresh screen 60 times per second
  for (int c=0;c<gOscChannels;c++) {
    for (int s=0;s<width;s++) {                 //set initial values to midrange
      values[c][s] = 0;
    }//for each sample
  }//for each channel 
  if (saveAsText) {
    Date d = new Date();
    long timestamp = d.getTime() ;
    String date = new java.text.SimpleDateFormat("yyyyMMddHHmmss").format(timestamp);
    String storagePath = System.getProperty("user.home")+ File.separator+ date+ ".txt"; 
    print("Saving data to file "); println( storagePath);
    output = createWriter(storagePath);    
  }
  ads_setupSimple();
  //ads_setup();
  
} //setup() 

void serDecode() { //assuming Arduino is only transfering active channels
  int newlen = port.available();
  if (newlen < 1) return;
  int packetBytes = 1+(3 * gOscChannels); //8 bit header + 24-bits data per ACTIVE channel
  int len = newlen + residualBytes;
  int[] rawData = new int [len];
  if (residualBytes > 0)
    for (int c=0; c <residualBytes; c++)
      rawData[c] = residualRawData[c];    
  for (int c=0; c <newlen; c++)
    rawData[residualBytes+c] = port.read();
  int pos = 0;
  int OKpos = -1;
  //print(newlen);print("+");print(residualBytes);print("=");print(len);print(":");println(packetBytes);
  while (pos < len) {  //read the latest value
    if (((len-pos) >= packetBytes) && ( (rawData[pos]>>4) !=  12) ) {
      print('*'); //ERROR: most significant 4 bits of status byte should be 1100
     pos = pos + 1; 
    } else if ((len-pos) >= packetBytes) {       
        
      for (int i = 0; i < gOscChannels; i++) //first byte is status, then 3 bytes per channel
             val[i] =  ( rawData[pos+1+(i*3)]  << 24) +(rawData[pos+2+(i*3)]  << 16) +(rawData[pos+3+(i*3) ]<<8) ; //load as 32bit to capture sign bit
         for (int i = 0; i < gOscChannels; i++)
             val[i] = (val[i] >> 8); //convert 32-bit to 24-bit integer processing deals with the sign, 
         
         if (saveAsText) {
             if (gOscChannels > 1) {
               for (int i = 0; i < (gOscChannels-1); i++)
                 output.print(val[i] + "\t");
             } //if multiple channels
             output.println(val[gOscChannels-1]);
           }//if saveAsText
           
          if (autoScale) {
            for (int i = 0; i < gOscChannels; i++) {
              if (val[i] > channelMax[i]) {
                channelMax[i] =  val[i];
                autoScaleChannel(i);
              }//new max
              if (val[i] < channelMin[i]) {
                channelMin[i] =  val[i];
                autoScaleChannel(i);
              } //new min                    
            }//for each channel
          } //if autoScale
           
           if (calibrationFrames == 0) { //drawing display
              lastSamplePlotted = (lastSamplePlotted + pixelsPerSample);
              if (lastSamplePlotted >= 1) { //draw new sample[s]
                for (int i = 0; i < gOscChannels; i++) 
                  val[i] = round(float(val[i]-  channelMin[i])*channelSlope[i])+channelIntercept[i];  
                for (int px = 0; px < floor(lastSamplePlotted); px++) {
                  for (int ch = 0; ch < gOscChannels; ch++) values[ch][cnt] = val[ch];  //put it in the array
                  cnt++;  //increment the count
                  if (cnt > wm1) cnt = 1;
                }
              } 
              lastSamplePlotted = lastSamplePlotted - floor(lastSamplePlotted);
           } else //if calibrationframes = 0 else still calibrating...
             valuesReceived++;
          
            pos = pos+packetBytes;
            OKpos = pos-1;
            //print("."); //report valid sample
         
     } else { //if not commmand
        pos = pos + 1; 
     } //single byte
  } //while samples to read
  //deal with partial packets
  residualBytes = (len-1) - OKpos; //bytes we were unable to use, e.g. 1024 bytes sent, 1022 read 
  if (residualBytes > maxResidualBytes) residualBytes = maxResidualBytes;
  if (residualBytes > 0)
       for (int i = 0; i < residualBytes; i++)
         residualRawData[i] = rawData[len-residualBytes+i]; 
} //void serDecode
/*
// the code below is only used if Arduino code comments out "#define txActiveChannelsOnly"
//this format send unused channels, requiring a lot more bandwidth when gOscChannels < kOscMaxChannels
void serDecodeBig() { 
  int newlen = port.available();
  if (newlen < 1) return;
  int packetBytes = (3 * (kOscMaxChannels+1)); //24 bit header + 24-bits data per channel
  int len = newlen + residualBytes;
  int[] rawData = new int [len];
  if (residualBytes > 0)
    for (int c=0; c <residualBytes; c++)
      rawData[c] = residualRawData[c];    
  for (int c=0; c <newlen; c++)
    rawData[residualBytes+c] = port.read();
  int pos = 0;
  int OKpos = -1;
  //print(newlen);print("+");print(residualBytes);print("=");print(len);print(":");println(packetBytes);
  while (pos < len) {  //read the latest value
    if (((len-pos) >= packetBytes) && ( (rawData[pos]>>4) !=  12) ) {
      print("*"); //ERROR: most significant 4 bits of status byte should be 1100
     pos = pos + 1; 
    } else if ((len-pos) >= packetBytes) {       
         for (int i = 0; i < gOscChannels; i++) //first 3 bytes are status, then 3 bytes per channel
             val[i] =  ( rawData[pos+3+(i*3)]  << 24) +(rawData[pos+4+(i*3)]  << 16) +(rawData[pos+5+(i*3) ]<<8) ; //32bit
         for (int i = 0; i < gOscChannels; i++)
             val[i] = (val[i] >> 8)+8388608; //convert 32 bit to 24 bit, baseline correct
         
         if (saveAsText) {
             if (gOscChannels > 1) {
               for (int i = 0; i < (gOscChannels-1); i++)
                 output.print(val[i] + "\t");
             } //if multiple channels
             output.println(val[gOscChannels-1]);
           }//if saveAsText
           
           if (calibrationFrames == 0) { //drawing display
              lastSamplePlotted = (lastSamplePlotted + pixelsPerSample);
              if (lastSamplePlotted >= 1) { //draw new sample[s]
                for (int i = 0; i < gOscChannels; i++) val[i] = round(val[i]*screenScale24bit);  
                if (offsetTraces)
                  for (int i = 0; i < gOscChannels; i++) val[i] = val[i] + (i*2) - (gOscChannels-1); 
                for (int px = 0; px < floor(lastSamplePlotted); px++) {
                  for (int ch = 0; ch < gOscChannels; ch++) values[ch][cnt] = val[ch];  //put it in the array
                  cnt++;  //increment the count
                  if (cnt > wm1) cnt = 1;
                }
              } 
              lastSamplePlotted = lastSamplePlotted - floor(lastSamplePlotted);
           } else //if calibrationframes = 0 else still calibrating...
             valuesReceived++;
           
            pos = pos+packetBytes;
            OKpos = pos-1;
            //print("."); //report valid sample
         
     } else { //if not commmand
        pos = pos + 1; 
     } //single byte
  } //while samples to read
  //deal with partial packets
  residualBytes = (len-1) - OKpos; //bytes we were unable to use, e.g. 1024 bytes sent, 1022 read 
  if (residualBytes > maxResidualBytes) residualBytes = maxResidualBytes;
  if (residualBytes > 0)
       for (int i = 0; i < residualBytes; i++)
         residualRawData[i] = rawData[len-residualBytes+i]; 
} //void serDecode
*/

void draw() {
  //if (terminateAll) return;
      serDecode();
      if (calibrationFrames > 0) {
        if ((startTime == 0) && (valuesReceived > 0)){
          valuesReceived = 0; 
          startTime = millis();
        }
        calibrationFrames--;
        if (calibrationFrames == 0) {
          calibrateFrameRate(); 
        }
        return;
      } //if still in initial calibration frames period
      //NEXT : DRAW GRAPH
      background(96); // background 0 = black, 255= white
      //next: vertical lines for seconds...
      stroke(60);
      float xpos = tickSpacing;
      while (xpos < width) {  
        line(xpos,0,xpos,screenHt);  
        xpos = xpos + tickSpacing;
      }
      //draw the leading edge line
      stroke(255,255,0);
      line(cnt,halfScreenHt-positionHt,cnt,halfScreenHt+positionHt);  
      //plot incoming data      
      for (int i = 0; i < gOscChannels; i++) {
        stroke(lineColorsRGB[i][0],lineColorsRGB[i][1],lineColorsRGB[i][2]);  
        for (int x=2; x<wm1; x++) line (x-1,  values[i][x-1], x, values[i][x]);
      }        
 } //draw()
