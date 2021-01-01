#define BAUD_RATE  460800 //specifies BlueTooth speed. top speeds appear to be around 115200 for Due, 460800 for Teensy3
#define txActiveChannelsOnly //reduce bandwidth: only send data for active data channels

#if defined(__SAM3X8E__)
  #define isDUE  //Detect Arduino Due
  #define WiredSerial SerialUSB //use Due's Native port
#else  
  #define WiredSerial Serial
#endif

#include "ads1298.h"
#include "adsCMD.h"
#include <SPI.h>  // include the SPI library:
int gMaxChan = 0;
int gNumActiveChan = 0;
int activeSerialPort = 0; //data will be sent to serial port that last sent commands. E.G. bluetooth or USB port
boolean gActiveChan [9]; // reports whether channels 1..9 are active
const int kPIN_LED = 13;//pin with light - typically 13. Only flashes if error status. n.b. on Teensy3, pin 13 is ALSO spi clock!
boolean isRDATAC = false;


void detectActiveChannels() {  //set device into RDATAC mode -it will stream data
  if ((isRDATAC) ||  (gMaxChan < 1)) return; //we can not read registers when in RDATAC mode
  using namespace ADS1298; 
  gNumActiveChan = 0;
  for (int i = 1; i <= gMaxChan; i++) {
    delayMicroseconds(1); 
     int chSet = adc_rreg(CHnSET + i);
     gActiveChan[i] = ((chSet & 7) != SHORTED);
     if ( (chSet & 7) != SHORTED) gNumActiveChan ++;   
  }
}

int Serialavailable(int serialNum) { //handle commands to ADS device
  switch (serialNum) {
    case 1:
      return Serial1.available() ;
    default: 
      return WiredSerial.available() ;
  }
}

int Serialread(int serialNum) { //handle commands to ADS device
  switch (serialNum) {
    case 1:
      return Serial1.read() ;
    default: 
      return WiredSerial.read() ;
  }
}

void checkSerialNum(int serialNum) { //handle commands to ADS device
  if (Serialavailable(serialNum) < 1) return;
  activeSerialPort = serialNum;
  unsigned char  val = Serialread(serialNum);      
  using namespace ADS1298; 
  if ((val >= 0x02) && (val <= 0x12)) { //single byte command
        if (val == RDATAC) {
          detectActiveChannels(); //start streaming data
          if (gNumActiveChan > 0) isRDATAC = true;
        }
        if (val == SDATAC) isRDATAC = false;
        if (val == RDATA) isRDATAC = false;
        adc_send_command(val);
        return;
  }
  if ((val >= 0x20) && (val <= 0x3F)) { //RREG (Read register) command  
      for (int i = 0; i < 10; ++i) if (Serialavailable(serialNum) < 1) delay(1); 
      if(Serialavailable(serialNum) < 1) return;
      unsigned char  numSerialBytes = Serialread(serialNum)+1;
      digitalWrite(IPIN_CS, LOW);
      SPI.transfer(val);
      SPI.transfer(numSerialBytes-1);	// number of registers to be read – 1
      unsigned char serialBytes[numSerialBytes];
      for (int i = 0; i < numSerialBytes; ++i) 
        serialBytes[i] =SPI.transfer(0);
      delayMicroseconds(1);     
      digitalWrite(IPIN_CS, HIGH);
      switch (serialNum) {
        case 1:
          Serial1.write(serialBytes, numSerialBytes);
          Serial1.flush();
          break;
        default: 
            WiredSerial.write(serialBytes, numSerialBytes);
            WiredSerial.flush();
      }
      return;
  }
  if ((val >= 0x40) && (val <= 0x5F)) { //WREG (Write Register) command
      for (int i = 0; i < 5; ++i) if (Serialavailable(serialNum) < 1) delay(1); 
      if(Serialavailable(serialNum) < 1) return;
      unsigned char  numSerialBytes = Serialread(serialNum)+1;
      for (int i = 0; i < 5; ++i) if (Serialavailable(serialNum) < numSerialBytes) delay(1); 
      if(Serialavailable(serialNum) < numSerialBytes) return;
      unsigned char serialBytes[numSerialBytes];
      for (int i = 0; i < numSerialBytes; ++i) serialBytes[i] = Serialread(serialNum); 
      digitalWrite(IPIN_CS, LOW);
      SPI.transfer(val);
      SPI.transfer(numSerialBytes-1);	// number of registers to be written – 1
      for (int i = 0; i < numSerialBytes; ++i) {
        SPI.transfer(serialBytes[i]);
        delayMicroseconds(1);      
      }
      digitalWrite(IPIN_CS, HIGH);
  }//if WREG
}

//#define testSignal //use this to determine if your software is accurately measuring full range 24-bit signed data -8388608..8388607
#ifdef testSignal
  int testInc = 1;
  int testPeriod = 100;
  byte testMSB, testLSB; 
#endif 

void sendOsc(void) { 
    if ((!isRDATAC) || (gNumActiveChan < 1) )  return;
    if (digitalRead(IPIN_DRDY) == HIGH) return; 
    digitalWrite(IPIN_CS, LOW);
    #ifdef txActiveChannelsOnly
      int numSerialBytes = 1 + (3 * gNumActiveChan); //8-bits header plus 24-bits per ACTIVE channel
      unsigned char serialBytes[numSerialBytes];
      int i = 0;
      serialBytes[i++] =SPI.transfer(0); //get 1st byte of header
      SPI.transfer(0); //skip 2nd byte of header
      SPI.transfer(0); //skip 3rd byte of header
      for (int ch = 1; ch <= gMaxChan; ch++) {
        if (gActiveChan[ch]) {
           #ifdef testSignal
            //positive full-scale input produces  7FFFFFh, negative full-scale input produces 800000h, neutroal produces 000000h 
            testInc++;
            if (testInc >= testPeriod) {
              testInc = 1;
              if (testMSB == 0x7F) { //send minimum value -8388608;
                testMSB = 0x80;
                testLSB = 0x00;
              } else if (testMSB == 0x80) { //send zero
                testMSB = 0x00;
                testLSB = 0x00;             
              } else { //send maximum value +8388607
                testMSB = 0x7F;
                testLSB = 0xFF;
              } 
            }
            serialBytes[i++] = testMSB;
            serialBytes[i++] = testLSB;
            serialBytes[i++] = testLSB;
            SPI.transfer(0); SPI.transfer(0); SPI.transfer(0);
          #else //if testSignal otherwise report real data
            serialBytes[i++] =SPI.transfer(0);
            serialBytes[i++] =SPI.transfer(0);
            serialBytes[i++] =SPI.transfer(0); 
          #endif
        } else {
          SPI.transfer(0); SPI.transfer(0); SPI.transfer(0); //skip these 24 bytes
        }  
      }
      //for (int i = 0; i < numSerialBytes; ++i) 
      //  serialBytes[i] =SPI.transfer(0);
    #else
      int numSerialBytes = (3 * (gMaxChan+1)); //24-bits header plus 24-bits per channel
      unsigned char serialBytes[numSerialBytes];
      for (int i = 0; i < numSerialBytes; ++i) 
        serialBytes[i] =SPI.transfer(0);
     #endif 
     delayMicroseconds(1); 
     digitalWrite(IPIN_CS, HIGH);
     switch (activeSerialPort) {
        case 1:
          Serial1.write(serialBytes, numSerialBytes);
          break;
        default: 
            WiredSerial.write(serialBytes, numSerialBytes);;
      }
}

void adsSetup() { //default settings for ADS1298 and compatible chips
        using namespace ADS1298;
        // All GPIO set to output 0x0000: (floating CMOS inputs can flicker on and off, creating noise)
	adc_wreg(GPIO, 0);
        adc_wreg(CONFIG3,PD_REFBUF | CONFIG3_const);
	//FOR RLD: Power up the internal reference and wait for it to settle
        // adc_wreg(CONFIG3, RLDREF_INT | PD_RLD | PD_REFBUF | VREF_4V | CONFIG3_const);
	// delay(150);
	// adc_wreg(RLD_SENSP, 0x01);	// only use channel IN1P and IN1N
	// adc_wreg(RLD_SENSN, 0x01);	// for the RLD Measurement
        adc_wreg(CONFIG1,HIGH_RES_1k_SPS);
        adc_wreg(CONFIG2, INT_TEST);	// generate internal test signals
	// Set the first two channels to input signal
	for (int i = 1; i <= 8; ++i) {
		adc_wreg(CHnSET + i, ELECTRODE_INPUT | GAIN_12X); //report this channel with x12 gain
		//adc_wreg(CHnSET + i, TEST_SIGNAL | GAIN_12X); //create square wave
                //adc_wreg(CHnSET + i,SHORTED); //disable this channel
	}
	digitalWrite(PIN_START, HIGH);  
}

void setup(){
  using namespace ADS1298;
  //prepare pins to be outputs or inputs
  //pinMode(PIN_SCLK, OUTPUT); //optional - SPI library will do this for us
  //pinMode(PIN_DIN, OUTPUT); //optional - SPI library will do this for us
  //pinMode(PIN_DOUT, INPUT); //optional - SPI library will do this for us
  pinMode(IPIN_CS, OUTPUT);
  pinMode(PIN_START, OUTPUT);
  pinMode(IPIN_DRDY, INPUT);
  //pinMode(PIN_CLKSEL, OUTPUT);//*optional
  //pinMode(IPIN_RESET, OUTPUT);//*optional
  //pinMode(IPIN_PWDN, OUTPUT);//*optional
  //start small peripheral interface
  SPI.begin();
  SPI.setBitOrder(MSBFIRST);
  #ifndef isDUE
  SPI.setClockDivider(SPI_CLOCK_DIV4); //http://forum.pjrc.com/threads/1156-Teensy-3-SPI-Basic-Clock-Questions
  #endif
  SPI.setDataMode(SPI_MODE1);
  //Start ADS1298
  delay(500); //wait for the ads129n to be ready - it can take a while to charge caps
  //digitalWrite(PIN_CLKSEL, HIGH);//*optional
  //delay(1);digitalWrite(IPIN_PWDN, HIGH);//*optional - turn off power down mode
  //digitalWrite(IPIN_RESET, HIGH);delay(100);//*optional
  //digitalWrite(IPIN_RESET, LOW);delay(1);//*optional
  //digitalWrite(IPIN_RESET, HIGH);delay(1);  //*optional Wait for 18 tCLKs AKA 9 microseconds, we use 1 millisec
  // Send SDATAC Command (Stop Read Data Continuously mode)
  delay(100); //pause to provide ads129n enough time to boot up...
  adc_send_command(SDATAC);
  delay(10);
  // Determine model number and number of channels available
  int IDval = adc_rreg(ID) ; 
  switch (IDval & B00011111 ) { //least significant bits reports channels
          case  B10000: //16
            gMaxChan = 4; //ads1294
            break;
          case B10001: //17
            gMaxChan = 6; //ads1296
            break; 
          case B10010: //18
            gMaxChan = 8; //ads1298
            break;
          case B11110: //30
            gMaxChan = 8; //ads1299
            break;
          default: 
            gMaxChan = 0;
  }
  //start serial port
  Serial1.begin(BAUD_RATE);
  Serial1.flush(); //flush all previous received and transmitted data
  WiredSerial.begin(9600); //use native port on Due
  while (WiredSerial.read() >= 0) {} //http://forum.arduino.cc/index.php?topic=134847.0
  delay(200);  // Catch Due reset problem
  //while (!WiredSerial) ; //required by Leonardo http://arduino.cc/en/Serial/IfSerial (ads129n requires 3.3v signals, Leonardo is 5v)
  if (gMaxChan == 0) { //error mode
    pinMode(kPIN_LED, OUTPUT);
    while(1) { //loop forever 
      digitalWrite(kPIN_LED, HIGH);   // turn the LED on (HIGH is the voltage level)
      delay(500);               // wait for a second
      digitalWrite(kPIN_LED, LOW);    // turn the LED off by making the voltage LOW
      delay(500); 
    } //while forever
  } //error mode
  adsSetup(); //optional - sets up device - the PC can do this as well       
} //setup()

void loop()
{
    //checkSerial(); //see if there are any new commands
    checkSerialNum(1); //wireless
    checkSerialNum(0); //wired
    sendOsc(); //see if there are any new samples to report
} //loop()


