function adsScopeMath
%adsScopeMath a simple oscilloscope for ads1298 family of chips (1294,1296,198,1299) 
%
%   adsSCOPEMATH_ARDUINO was derived from SCOPEMATH_SIMPLE.
%   It displays data from the ads1298 via a serial port 
%   Unlike other versions of ScopeMath, adsScopeMath does not use the Instrument Control Toolbox. 
%
% The user has the option to save the data to BrainVision Analyzer Format
%  You can analyze BrainVision files with EEGLAB, ELEcro, or other tools
%
% Arduino acquisition code is in startDeviceType1, getDataFromDeviceType1, stopDeviceType1 
% Simulated acquisition code is in startDeviceType0, getDataFromDeviceType0, stopDeviceType0 
%  This makes it easy to add a new deviceType, e.g. startDeviceType2, getDataFromDeviceType2, stopDeviceType2 
%
% THE ARDUINO MUST BE RUNNING THE SKETCH FROM
%   http://www.mccauslandcenter.sc.edu/CRNL/tools/oscilloscope
%
%   NOTE: This function requires MATLAB ver. 7.0 or later.  
%
%   Derived from ScopeMath_Simple (available on the MATLAB File Exchange) August-21-2007 (Gautam.Vallabha@mathworks.com)
%   Version 1.0 March-19-2013 (Chris Rorden)

global v
v.hzChoices = [250 500 1000 2000 4000]; %acquisition rate: maximum depends on hardware 
v.chChoices = [1 2 3 4 5 6 7 8]; %number of channels: maximum depends on hardware (Leonardo supports 6, Teensy3 supports 14)
v.saveDataDefault = 0; %if 1 data will be saved to disk by default, if 0 data will be discarded
v.hzDefaultIndex = 1; %e.g. if 2, 2nd option of HzChoices is the default
v.chDefaultIndex = 1; %e.g. if 2, 2nd option of ChChoices is the default
v.serDefaultIndex = 0; % 0 for auto-select, 1 for simulated data, 2 for Arduino on port 1, 3 for Arduino on port 3, etc
v.gGraphTotalTimeSec = 2.0; %e.g. if 1 then the last 1 second of data is displayed
v.AutoScaleAxis = true; 
v.testSignal =true;
%Typically no need to edit lines below.... 
v.gSecPerScreenRefresh = 0.1; %e.g. if 0.1 then screen is updated 10 times per second
v.deviceType = 0; %0 for simulated data, 1 for Arduino 
v.gOscHz = 100; %current sampling rate
v.gOscChannels = 1; %current number of channels we are recording
v.showPower = false; %should we conduct a FFT on recent data?
v.gSecPerSample = [];
v.gGraphSamples = []; 
v.xData = []; %time values for samples
v.yData = []; %most recent data channels*samples
v.gUnsavedData = []; %data not yet saved to disk
v.xUnits = 'Sec'; 
v.yUnits = 'Signal';
v.gSaveNumber = 1; %counts time since last save
v.gSaveEveryNRefreshes = 10; %eg. if 10, then we will save to disk every tenth screen update
v.gSampleNumber = 1; %only used to determine phase for simulated data
v.gSaveDataBaseFilename = []; %
v.kBPS = 460800; %baud rate for device
% GUI variables
v.hFigure = [];
v.hAxisRaw = [];%[0 xData(end) -1 1];
v.hAxesRaw = [];
v.hAxesMath = [];
v.hStartButton = [];
v.hTriggerCheck = [];
v.hSaveCheck = [];
v.hSerialPopup = []; %popup menu lists available serial ports
v.hChannelPopup = []; %popup menu lists available channels to record
v.hHzPopup = []; %popup menu lists available sampling rates
v.acquiringData = false; %are we currently sampling data?
v.serialObj = []; %serial port
v.rawData = []; %raw data from device - data that still needs to be decoded into discrete samples
% set up a timer to periodically get the data 
v.timerObj = timer('Period', v.gSecPerScreenRefresh, 'ExecutionMode', 'fixedSpacing', 'timerFcn', {@getDataFromDeviceType});
makeGUI(); %set up user interface

  %%---------------------------------------------------
   function getDataFromDeviceType(hObject, eventdata)
       global v;
       switch v.deviceType
        case 1
            [newData] = getDataFromDeviceType1();
           otherwise
            [newData] = getDataFromDeviceType0();
           
        end; %switch deviceType 
     
     if length(newData) < 1
         return
     end;
     v.yData = [v.yData newData]; %append new data
     v.yData = v.yData(:,length(v.yData)-v.gGraphSamples+1:end);
     if ~isempty(v.gSaveDataBaseFilename)
        v.gUnsavedData  = [v.gUnsavedData newData]; %append new data
        v.gSaveNumber = v.gSaveNumber + 1;
        if (v.gSaveNumber > v.gSaveEveryNRefreshes)  %flush unsaved data to disk
            flushSaveDataSub();
        end; %if SaveNumber
     end %if SaveData
     % check the user closed the window while we were waiting
     % for the device to return the waveform data
     if ishandle(v.hFigure),       
        axes(v.hAxesRaw);
        plot(v.xData,v.yData);
        if (v.AutoScaleAxis == false)
            axis(v.hAxisRaw);
        end;
        xlabel(v.xUnits); ylabel(v.yUnits);
        if v.showPower
            axes(v.hAxesMath);
            [freq,fftdata] = powerSpectrum(v.xData, v.yData);
            plot(freq, fftdata);
            xlabel('Frequency (Hz)'); ylabel('Amplitude');
        end;%showPower
     end
   %end getDataFromDeviceType()

  %%---------------------------------------------------
    function [newSamples0] = getDataFromDeviceType0()       
        %create - we create precisely the same number of observations per
        %  screen refresh, so sampling rate may be approximate
        global v;
        new = round(v.gOscHz*v.gSecPerScreenRefresh);
        if (new < 1) 
            new = 1;
        end
        
        for s = 1:new,
            for c=1:v.gOscChannels,
                newSamples0(c,s) = sin(30*2*pi*(v.gSecPerSample*(s+v.gSampleNumber)) ) + randn()*0.2; 
            end;
        end
        v.gSampleNumber = v.gSampleNumber + new;
        
   %end getDataFromDeviceType0()

  %%---------------------------------------------------
    function [newSamples1] = getDataFromDeviceType1()        
        global v;
        packetBytes = 4 + (2 * (v.gOscChannels-1)); %16-bits data per channel plus 4 bytes header
        count = packetBytes;
        if (v.serialObj.BytesAvailable + length(v.rawData)  < packetBytes) 
            newSamples1 = [];
            return;
        end;
        [newRawData,count] = fread(v.serialObj,v.serialObj.BytesAvailable,'uchar');
        %fprintf('serial bytes: %d new and %d left from previous samples \n', length(newRawData), length(rawData));
        v.rawData = [v.rawData; newRawData];
        if (length(v.rawData) < 1) 
            return;
        end;
        [newSamples1, v.rawData] = serDecodeSub(v.rawData);
   %end getDataFromDeviceType1()

  %%---------------------------------------------------         
   function [freq,fftdata] = powerSpectrum(x,y)
      n = length(x);
      Fs = 1/(x(2)-x(1));
      freq = ((0:n-1)./n)*Fs;
      fftdata = 20*log10(abs(fft(y)));
      idx = 1:floor(length(freq)/2);
      freq = freq(idx);
      fftdata = fftdata(idx);
   %end powerSpectrum()
   
  function figureKeyPress(ObjH, EventData)
%Powerpoint wireless presenter devices generat pageup/pagedown and hide
      %http://www.mathworks.com/matlabcentral/fileexchange/22334-keyboardnavigate/content/keyboardnavigate.m
      global v;
      if length(EventData.Modifier) == 0 ;%Normal mode; no modifier pressed
        switch EventData.Key 
            case 'pageup' 
                disp('pup');
            case 'pagedown' 
                disp('pdwn'); %to determine other keys
            otherwise
                %disp(double(EventData.Key));
        end;
      end;%no modifier
      Key = get(ObjH, 'CurrentCharacter');
      switch Key
         %case 27 %F5/escape key
         %    disp('escape');
         case 46 %monitor hide key
            startStopCallback(v.hStartButton,[]);
            disp('hide');
         otherwise
             %disp(double(Key)); %to determine other keys
     end; %switch deviceType   


  %%---------------------------------------------------   
   function makeGUI()
      global v;
      %v.hFigure = figure('deleteFcn', {@figureCloseCallback},'name',mfilename,'units','pixels','position',[40, 40, 1024, 512]);
      v.hFigure = figure('deleteFcn', {@figureCloseCallback},'name',mfilename,'units','pixels','position',[40, 40, 1024, 512],'KeyPressFcn', @figureKeyPress);

      if v.showPower
        v.hAxesRaw  = axes('position', [0.05  0.60  0.9 0.35]);
        title('Raw Data');
        v.hAxesMath = axes('position', [0.05  0.15  0.9 0.35]);      
        title('Processed Data');
      else
        v.hAxesRaw  = axes('position', [0.05  0.15  0.9 0.80]);
        title('Raw Data');
      end;
      v.hStartButton = uicontrol('Style', 'PushButton','String', 'Start Acquisition','units', 'pixels','position', [5 10 100 20],'callback', {@startStopCallback});
      v.hSaveCheck = uicontrol('Style','checkbox','units', 'pixels','position', [110 10 80 20],'string','Save Data','Value',v.saveDataDefault);
      v.hHzText = uicontrol('Style', 'text','units', 'pixels','position', [200 8 20 20],'String', 'Hz:', 'backgroundcol', get(gcf, 'color')); 
      v.hHzPopup = uicontrol('Style', 'popupmenu','units', 'pixels','position', [221 10 80 20],'String', v.hzChoices,'Value' , v.hzDefaultIndex); 
      v.hChannelText = uicontrol('Style', 'text','units', 'pixels','position', [300 8 50 20],'String', 'Channels:', 'backgroundcol', get(gcf, 'color'));
      v.hChannelPopup = uicontrol('Style', 'popupmenu','units', 'pixels','position', [351 10 70 20],'String', v.chChoices,'Value' , v.chDefaultIndex); 
      %v.hTriggerCheck = uicontrol('Style','checkbox','units', 'pixels','position', [760 10 80 20],'string','Outputs On','Value',0,'callback', {@triggerCallback});
      if (ispc) %provide list of serial ports
          if (exist('winqueryreg') == 0) %this will always work... 
                ser = cellstr(strvcat('Simulate data', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8'));
                if v.serDefaultIndex == 0
                    v.serDefaultIndex = 1;
                end;
            else %Below... hopefully this also works
                %[ok, ser] = system('powershell [System.IO.Ports.SerialPort]::getportnames()'); %<-good in theory, too slow in practice
                %see http://www.mathworks.com/matlabcentral/newsreader/view_thread/265836
                devices = winqueryreg('name', 'HKEY_LOCAL_MACHINE', 'HARDWARE\DEVICEMAP\SERIALCOMM');
                if length(devices) > 0
                    ser = [];
                    for (d = 1:length(devices))
                        ser = [winqueryreg('HKEY_LOCAL_MACHINE', 'HARDWARE\DEVICEMAP\SERIALCOMM', devices{d}), ser ];
                    end;
                    
                    ser = regexp(ser,'\s','split');
                    ser = ser(~cellfun(@isempty, ser)); %deblank
                    ser = ['Simulate data', ser ];
                else
                   ser = cellstr(strvcat('Simulate data')) 
                end %devices not empty

                if v.serDefaultIndex == 0
                    v.serDefaultIndex = length(ser);
                end;
            end;
      else
        [ok, ser] = system('ls /dev/cu.*');
        ser = regexp(ser,'\s','split');
        ser = ser(~cellfun(@isempty, ser)); %deblank
        ser = ['Simulate data', ser ];
      if (v.serDefaultIndex == 0) %Arduino/Teensy have names like /dev/cu.usbmodem12341 or /dev/cu.usbmodemfa131, our bluetooth will be named /dev/cu.us922kBT0000 
        Index = find(not(cellfun('isempty', strfind(ser, 'us'))));
        if isempty(Index)
            v.serDefaultIndex = 1;
        else
            v.serDefaultIndex = Index(1); %choose first port that matches our search string
        end;
       end; %serDefaultIndex = 0
      end; %if ispc else
      if v.serDefaultIndex >  length(ser) %user specified a port that does not exist
          v.serDefaultIndex =  length(ser);
      end;    
      v.hSerialPopup = uicontrol('Style', 'popupmenu','units', 'pixels','position', [560 10 200 20],'String', ser,'Value' , v.serDefaultIndex); 
      set(v.hStartButton, 'callback', {@startStopCallback});
   %end %makeGUI()
  
  %%---------------------------------------------------
    function[OK] =  startDeviceType()
    global v;
    v.gUnsavedData = [];
    v.rawData = []; %raw data from device - data that still needs to be decoded into discrete samples
    %v.newSamples = []; %samples acquired in most recent screen refresh
    v.gOscHz = v.hzChoices(get(v.hHzPopup,'Value'));
    v.gOscChannels = v.chChoices(get(v.hChannelPopup,'Value'));
    v.gSecPerSample = 1/v.gOscHz;
    v.gGraphSamples = round(v.gOscHz * v.gGraphTotalTimeSec);
    v.xData = linspace(0,v.gGraphSamples/v.gOscHz,v.gGraphSamples); 
    v.hAxisRaw = [0 v.xData(end) -1 1];
    v.gSampleNumber = 1;
    if get(v.hSaveCheck,'Value') == 1
        v.gSaveDataBaseFilename = saveBrainVisionSub([]);
        fprintf('Saving data as %s\n',v.gSaveDataBaseFilename);
    else
        v.gSaveDataBaseFilename = [];
        fprintf('Warning: data not being saved to disk\n');
    end %if gSaveData 
    if (get(v.hSerialPopup,'Value') == 1)
        v.deviceType = 0; %simulated data
        [OK] =startDeviceType0();
    else
        v.deviceType = 1; %arduino
        list=get(v.hSerialPopup,'String');
        val=get(v.hSerialPopup,'Value');
        [OK] =startDeviceType1 (list{val});
    end;   
    %v.hAxisRaw('auto y'); %v.hAxisRaw(3) = 0;  v.hAxisRaw(4) = 0;
    v.yData = zeros(v.gOscChannels,v.gGraphSamples);
   %end %startDeviceType()

  %%---------------------------------------------------
   function [OK] = startDeviceType0() %DeviceType 0 = simulated data
       global v; 
       fprintf('Simulated Data: Recording %d channels at %d Hz\n',v.gOscChannels,v.gOscHz);
       v.hAxisRaw(3) = -1.5;  v.hAxisRaw(4) = 1.5; %simulated signal in range -1..+1 plus noise
       OK = true;
   %end %startDeviceType0()
   
       function adc_send_command(cmd);
        global v;
           pause(0.001);
        fwrite(v.serialObj,[cmd]);           
           
       %end adc_send_command
    function adc_wreg(reg, val)
        %see pages 40,43 of ads1298r datasheet - 
        global v;
        pause(0.001);
        fwrite(v.serialObj,[64+reg,0,val]);
    %end adc_wreg
    
   function [val] =  adc_rreg(reg) %read register
       val = -1;
       global v; 
       if (v.serialObj.BytesAvailable > 0)
            fread(v.serialObj, v.serialObj.BytesAvailable); %flush buffer
       end;
       fwrite(v.serialObj,[32+reg,0]);
       for c=1:100%there is often some latency with USB communications
           if (v.serialObj.BytesAvailable < 1)
               pause(0.001);
           end
       end
       if (v.serialObj.BytesAvailable > 0)
        [data,count] = fread(v.serialObj,v.serialObj.BytesAvailable,'uchar');
        val = data(1);
       end
%end adc_rreg
    
  function [nMaxChan] = ads_getMaxChannels
  IDval =  adc_rreg(0); %read register: Identification
  if (IDval < 0) 
    error('No response from device - please check connections');
  end;
  switch bitand (IDval, 7)  %least significant bits reports channels
          case  0
            nMaxChan = 4; %ads1294
         case 1
            nMaxChan = 6; %ads1296
          case 2
            nMaxChan = 8; %ads1298
          case 6
            nMaxChan = 8; %ads1299
  end;
  if (IDval < 1) 
      nMaxChan = 0; %ensure device is really connected: bit 4 MUST be high
  end;
  fprintf('Channels available: %d  Device ID register value:  %d\n',nMaxChan,IDval);
%end  ads_getMaxChannels

   
   %%---------------------------------------------------
   function [OK] = startDeviceType1 (DeviceName) %DeviceType 1 = Arduino on serial port
       %    bandwidth = (gOscHz * ((gOscChannels*3)+1)) /(8 * kBPS); %packets are 4 bytes plus 2 bytes per analog channel  *8 = 8 bits per byte
       SDATAC = uint8(hex2dec('11'));
        RDATAC = uint8(hex2dec('10'));
        ID = uint8(hex2dec('00'));
        GPIO = uint8(hex2dec('14'));
        CONFIG3 = uint8(hex2dec('03'));
        RLDREF_INT = uint8(hex2dec('08'));
        PD_RLD = uint8(hex2dec('04'));
        PD_REFBUF = uint8(hex2dec('80'));
        VREF_4V = uint8(hex2dec('20'));
        CONFIG3_const = uint8(hex2dec('40'));
        RLD_SENSP = uint8(hex2dec('0d'));
        RLD_SENSN = uint8(hex2dec('0e'));
        CONFIG1 = uint8(hex2dec('01'));
        CONFIG2 = uint8(hex2dec('02'));
        CHnSET = uint8(hex2dec('04'));
        HR = uint8(hex2dec('80'));
        DR2 = uint8(hex2dec('04'));
        DR1 = uint8(hex2dec('02'));
        DR0 = uint8(hex2dec('01'));
        HIGH_RES_32k_SPS = uint8(HR);
        HIGH_RES_16k_SPS = uint8(HR+ DR0);
        HIGH_RES_8k_SPS = uint8(HR+ DR1);
        HIGH_RES_4k_SPS = uint8(HR+ DR1+ DR0);
        HIGH_RES_2k_SPS = uint8(HR+ DR2);
        HIGH_RES_1k_SPS = uint8(HR+ DR2+ DR0);
        HIGH_RES_500_SPS = uint8(HR+ DR2+ DR1);
        HIGH_RES_250_SPS = uint8(HR+DR2+ DR1);
        LOW_POWR_250_SPS = uint8(DR2+ DR1);
        LOW_POWR_1k_SPS = uint8(DR2+ DR0);
        INT_TEST = uint8(hex2dec('10'));
        TEST_AMP = uint8(hex2dec('00')); %double amplitude of test signal to 2 x -(VREFP-VREFN)/2.4mV
          %char TEST_AMP = uint8(hex2dec('04'); //double amplitude of test signal to 2 x -(VREFP-VREFN)/2.4m
        TEST_FREQ1 = uint8(hex2dec('02')); 
        TEST_FREQ0 = uint8(hex2dec('01')); 
        INT_TEST_4HZ_AMP = uint8(INT_TEST + TEST_AMP); %power saving 2Hz , precision 1Hz (0.98)
        INT_TEST_8HZ_AMP = uint8(INT_TEST + TEST_FREQ0 + TEST_AMP);  %power saving 4Hz highres = uint8(2 Hz (1.95)
        GAINn2 = uint8(hex2dec('40'));
        GAINn1 = uint8(hex2dec('20')); 
        GAIN_12X = uint8(GAINn2+ GAINn1);
        PDn = uint8(hex2dec('80')); %power down amplifier
        MUXn2 = uint8(hex2dec('04'));
         MUXn1 = uint8(hex2dec('02'));
        MUXn0 = uint8(hex2dec('01'));
        TEST_SIGNAL = uint8(MUXn2+ MUXn0);
        ELECTRODE_INPUT = uint8(hex2dec('00'));
        SHORTED = uint8(MUXn0);       
       %
       global v;
       OK = false; % assume failure to connect
        if (v.gOscChannels < 1) 
            fprintf('Error in %s: set gOscChannels to be at least 1\n',mfilename('fullpath'));            
            return;
        end;

        fcloseSerialSub();
        
        v.hAxisRaw(3) = -9000000;  v.hAxisRaw(4) = 9000000; %signed 24-bit acquisition data ranges -8388608..8388607
        v.serialObj=serDeviceIndexSub (DeviceName);
        adc_send_command(SDATAC); %stop any sampling - we will configure setup
        pause(0.1); %delay probably not required, but we need to be in SDATAC to change setup
        maxChan = ads_getMaxChannels;
        if (maxChan < 1)
            fprintf('Error in %s: unable to detect an ads1298-compatible system. Please check connections.\n',mfilename('fullpath'));            
            return;     
        end;
        if (maxChan < v.gOscChannels)
            fprintf('Error ads1298-compatible system can only support up to %d channels.\n',maxChan);            
            return;     
        end;
        OK = true;
        if isempty(DeviceName)
            fprintf('ads Data: Recording %d channels at %d Hz\n',v.gOscChannels-1,v.gOscHz);
        else
            fprintf('ads Data: Recording %d channels at %d Hz attached to port "%s"\n',v.gOscChannels-1,v.gOscHz,DeviceName);
        end;
        
         adc_wreg(GPIO, char(0));
           %register CONFIG1 sets sample rate, daisy-chain, resolution (high vs power saving) and CLK connection
          if (v.gOscHz < 375) 
            adc_wreg(CONFIG1, HIGH_RES_250_SPS);
          elseif (v.gOscHz < 750) 
            adc_wreg(CONFIG1,HIGH_RES_500_SPS);
          elseif (v.gOscHz < 1500) 
            adc_wreg(CONFIG1,HIGH_RES_1k_SPS);
          elseif (v.gOscHz < 3000)
            adc_wreg(CONFIG1,HIGH_RES_2k_SPS);
          elseif (v.gOscHz < 6000)
            adc_wreg(CONFIG1,HIGH_RES_4k_SPS);
          elseif (v.gOscHz < 12000)
            adc_wreg(CONFIG1,HIGH_RES_8k_SPS);
          elseif (v.gOscHz < 24000) 
            adc_wreg(CONFIG1,HIGH_RES_16k_SPS);
          else
            adc_wreg(CONFIG1,HIGH_RES_32k_SPS);
          end
           %register CONFIG1 sets WCT, internal/external test signal, test amplifier and test frequency
           adc_wreg(CONFIG2, INT_TEST_4HZ_AMP);  % generate internal test signals
           %register CONFIG3 sets multi-reference and RLD operation
           adc_wreg(CONFIG3,uint8(PD_REFBUF + CONFIG3_const)); %PD_REFBUF used for test signal
           %To use RLD:  Power up the internal reference and wait for it to settle
           % adc_wreg(CONFIG3,char( RLDREF_INT + PD_RLD + PD_REFBUF + VREF_4V + CONFIG3_const));
           % delay(150);
           %You would also specify which channels to use for RLD
           % adc_wreg(RLD_SENSP, char(0x01));  % only use channel IN1P and IN1N
           % adc_wreg(RLD_SENSN, char(0x01));  % for the RLD Measurement
           % Set channels to record 
           if (v.testSignal) 
             for i=1:v.gOscChannels 
               adc_wreg(uint8(CHnSET + i), uint8(TEST_SIGNAL+ GAIN_12X));
             end;
           else
             for i=1:v.gOscChannels 
               adc_wreg(uint8(CHnSET + i), uint8(ELECTRODE_INPUT + GAIN_12X));
             end
           end; %if testSignal else
          if (v.gOscChannels < 8)
            for i=(v.gOscChannels+1):8
               adc_wreg(uint8(CHnSET + i), uint8(PDn + SHORTED));  %turn off unused amplifiers 
            end
          end;
         v.gOscChannels = v.gOscChannels + 1; %include extra channel for digital data 
        adc_send_command(RDATAC); %restart streaming
   %end %startDeviceType1()

  %%---------------------------------------------------
   function stopDeviceType()
    global v;
    switch v.deviceType
     case 1
        stopDeviceType1();
     otherwise
         stopDeviceType0();
    end %switch deviceType 
    flushSaveDataSub(); %save any residual data to disk
    fcloseSerialSub();
   %end %stopDeviceType()

   function stopDeviceType0(v)
         disp('Simulated acquisition halted');
   %end %stopDeviceType0()

  %%---------------------------------------------------
   function stopDeviceType1()
       global v; 
       disp('Arduino acquisition halted');
       if ~isnumeric(v.serialObj) &&  isvalid(v.serialObj) 
        SDATAC = uint8(hex2dec('11'));
        adc_send_command(SDATAC); %stop any sampling - we will configure setup

       end;
   %end %stopDeviceType1()

  %%---------------------------------------------------
   function flushSaveDataSub()
    global v;
    if isempty(v.gSaveDataBaseFilename) 
        return; 
    end
    v.gSaveNumber = 1;
    saveBrainVisionSub(v.gUnsavedData,v.gOscHz,false, true, v.gSaveDataBaseFilename);
    v.gUnsavedData = [];
   %end; %flushSaveDataSub()  
  
   %%--------------------------------------------------- 
   function triggerCallback(hObject, eventdata)
       global v;
       if ~isnumeric(v.serialObj) &&  isvalid(v.serialObj) 
        
        %Cmd =[177,163,169,169];% [kCmd1Set kCmd2Mode,kCmd34ModeKey,kCmd34ModeKey];
        if get(v.hTriggerCheck,'Value') == 1
            fwrite(v.serialObj,127);
        else
            fwrite(v.serialObj,0);
        end;
       end;
   %end triggerCallback();
   
   
  %%---------------------------------------------------   
   function startStopCallback(hObject, eventdata)
       global v;
       if v.acquiringData
         if strcmp(v.timerObj.running, 'on')
            stop(v.timerObj);      
         end
         stopDeviceType;
         v.acquiringData = false;
         set(hObject, 'string', 'Start Acquisition');
         controlStatus = 'on';
      else
          OK = startDeviceType();
          if OK == false
            return;
          end;
          v.acquiringData = true;
         set(hObject, 'string', 'Stop Acquisition');
         controlStatus = 'off';
         if strcmp(v.timerObj.running, 'off')
             start(v.timerObj);
         end
       end         
       set(v.hSaveCheck,'Enable',controlStatus);
       set(v.hSerialPopup,'Enable',controlStatus);
       set(v.hChannelPopup,'Enable',controlStatus);
       set(v.hHzPopup,'Enable',controlStatus);  
   %end %startStopCallback()

  %%---------------------------------------------------   
   function figureCloseCallback(hObject, eventdata)
       global v;
       cleanupObjects();
   %end %figureCloseCallback()

  %%---------------------------------------------------   
   function cleanupObjects()
       global v;
       if isvalid(v.timerObj) 
         stop(v.timerObj); 
         delete(v.timerObj);
      end
      fcloseSerialSub();
      if ishandle(v.hFigure), 
         delete(v.hFigure); 
      end
   %end %cleanupObjects()

  %%---------------------------------------------------   
   function fcloseSerialSub()
       global v;
       if ~isnumeric(v.serialObj) &&  isvalid(v.serialObj) 
        if (v.serialObj.BytesAvailable > 0)
            fread(v.serialObj, v.serialObj.BytesAvailable); %flush buffer
        end;
        SDATAC = uint8(hex2dec('11'));
        adc_send_command(SDATAC); %stop any sampling - we will configure setup

        fclose(v.serialObj); 
        delete(v.serialObj);
        disp('closed serial port');
      end
   %end %fcloseSerialSub()

  %%---------------------------------------------------
   function [theSamples, rawResidual] =serDecodeSub(rawData)
       global v; 
       theSamples =[];
        len = length(rawData);
        samples = 0;
        packetBytes = 1 + (3 * (v.gOscChannels-1)); %24-bits data per channel plus 1 byte header
        pos = 1;
        OKpos = 0;
        while ((len-pos+1) >= packetBytes) 
           if (bitand(rawData(pos), 240) == 192 ) %header byte always starts binary 1100xxxx
            samples = samples + 1;
            for i=1:(v.gOscChannels-1)
                %the code below works on Intel based OSX computers, may not work on computers with different endian-ness 
                theSamples(i,samples) = typecast(uint8([0 rawData(pos+(i*3)) rawData(pos-1+(i*3)) rawData(pos-2+(i*3)) ]), 'int32'); %matlab does not natively support signed 24-bit, so create signed 32-bit
                theSamples(i,samples) = bitshift(theSamples(i,samples),-8); %convert 32-bit to 24-bit
            end;
            theSamples(v.gOscChannels,samples) = bitand(rawData(pos),15); %digital data
            pos = pos + packetBytes;
            OKpos = pos -1;%last valid byte
           else
          	pos = pos + 1;
           end; %if command else data
        end;
        if (OKpos < len) 
            %We need to retain left over bytes. Consider if the serial port transfers blocks of 512 bytes, but the expected packet
            %sise is 6 bytes, there will always be left over bytes
            %fprintf(' residual bytes: decoded %d of %d bytes (packet size %d)\n', OKpos,len,packetBytes );
            rawResidual = rawData((OKpos+1):end);
        else
            rawResidual = [];
            %fprintf('Perfect decoding\n');
        end;
        %length(newSamples);
        %if (pos < len)
        %    fprintf('partial transfer pos %d len %d packetBytes %d residual %d precision %d\n',pos, len, packetBytes, length(rawResidual), is16bit);
        %end;
    %end; % serDecodeSub()

  %%---------------------------------------------------
   function ser=serDeviceIndexSub(DeviceName)
        if ~nargin || isempty(DeviceName)
            if (ispc) 
                DeviceName = 'COM2';
            else
                %DeviceName = '/dev/tty.usbmodem12341';
                DeviceName = '/dev/cu.usbmodem12341';
            end;
        end; %DeviceName not specified
        if (ispc)
            fprintf('Assuming device is named "%s", use the Device Manager to show active ports.\n', DeviceName);   
        else
            fprintf('Assuming device is named "%s", available port names are\n', DeviceName);   
            system('ls /dev/cu.*');
        end;
        %ser = serial(DeviceName,'InputBufferSize',16384,'BaudRate',115200);% <-set large buffer, UNO very specifc about baud rate - others adaptable
        %ser = serial(DeviceName,'InputBufferSize',16384);
        ser = serial(DeviceName,'InputBufferSize',16384,'BaudRate',921600);%most reliable to set correct BPS - helps if device is already running at high speeds
        fopen(ser);
   %end % SerDeviceIndexSub()
   
   %%---------------------------------------------------   
    function [baseFilename] = saveBrainVisionSub(data,sampleRateHz,finalChannelDigital, appendData, filename)
    %save data in BrainVisionAnalyzer format
    %   data : an array with channels*samples of data
    %   sampleRateHz : sampling rate in Hz, e.g. if 10ms per sample then 100 Hz
    %   finalChannelDigital : often last channel is digital data (codes conditions or button presses)
    %   appendData : if true, and filename.eeg exists new data will be added to existing data
    %   filename : [optional] base name of file, e.g. ~/dir/f1 will create files  ~/dir/f1.vhdr and ~/dir/f1.eeg
    %EXAMPLE
    %  samplingRateHz = 100;
    %  time = [1/samplingRateHz:1/samplingRateHz:1]; %one second of data
    %  freqHz1 =2.0;
    %  data(1,:) = sin(2*pi*freqHz1*time);
    %  freqHz2 =10.0;
    %  data(2,:) = sin(2*pi*freqHz2*time);
    %  plot(time,data)
    %  samples = length(data(1,:))
    %  channels = length(data(:,1))
    %  basename = saveBrainVision(data,samplingRateHz);
    %  %to append more data to this file
    %  saveBrainVision(data,samplingRateHz,false,true,basename);
    %FORMAT DETAILS
    %  see "Brain Vision Analyzer OLE Automation Reference Manual Version 1.05"
    %     campus.uni-muenster.de/fileadmin/einrichtung/biomag/EEG-Labor/VisionAnalyserReference.doc

    if ~exist('filename','var')
        baseFilename =  [pwd filesep datestr(now,'yymmdd_HHMMSS')];
    else
        baseFilename =  filename;
        %[pth,nam,ext] = fileparts(filename);
        %baseFilename = [pth filesep nam]; %<- option: strip file extension
    end;
    if (~exist('sampleRateHz','var') || (sampleRateHz == 0))
        sampleRateHz = 1000;
        fprintf('%s warning: assuming %dHz sampling rate\n', mfilename,sampleRateHz);
    end;
    if ~exist('finalChannelDigital','var')
        finalChannelDigital = false;
    end;
    if ~exist('appendData','var')
        appendData = false;
    end; 
    VECTORIZED = false; %Warning: vectorized data storage incompatible with appending data
    if (length(data) < 1) 
        %note: user can call this function with data=[] to get basefilename for future appends...
        %fprintf('%s warning: no data to save\n', mfilename);
        return;
    end;
    samples = length(data(1,:));
    channels = length(data(:,1));
    headerFilename = [baseFilename '.vhdr'];
    dataFilename = [baseFilename '.eeg'];
    prevSamples = 0;
    if ((appendData) && (exist(dataFilename) ) )
       fileInfo = dir(dataFilename);
       fileSize = fileInfo.bytes;
       if (mod(fileSize,(channels*4)) ~= 0) % singles are 4 bytes each
            fprintf('%s warning: unable to append data to %s - filesize should be evenly disible by channels*4 (size of single)\n', mfilename,dataFilename);
            return;
       end;
       prevSamples = fileSize/(channels*4); % singles are 4 bytes each
       %fprintf(' Appending to %s with %d samples \n',dataFilename, prevSamples);
    end
    %next: write header file
    f = fopen(headerFilename,'w'); %overwrite existing header
    fprintf(f, 'Brain Vision Data Exchange Header File Version 1.0\n');
    fprintf(f, '; Data created by Matlab script %s\n',mfilename);
    fprintf(f,  '[Common Infos]\n');
    [PTH,NAM,EXT] = fileparts(dataFilename);
    fprintf(f, 'DataFile=%s\n',[NAM, EXT]); %remove path from name or EEGLAB gets upset
    fprintf(f,  'DataFormat=BINARY\n');
    if VECTORIZED 
        fprintf(f,  'DataOrientation=VECTORIZED\n');
    else
        fprintf(f, 'DataOrientation=MULTIPLEXED\n');
    end;
    fprintf(f, 'DataType=TIMEDOMAIN\n');
    fprintf(f, 'NumberOfChannels=%d\n',channels);
    fprintf(f, 'SamplingInterval=%f\n',1000000/sampleRateHz);
    % SamplingInterval: Resolution in microseconds for data in the time domain and in hertz for data in the frequency domain.
    fprintf(f,  'DataPoints=%d\n',samples+prevSamples);
    fprintf(f,  '[Binary Infos]\n');
    fprintf(f,  'BinaryFormat=IEEE_FLOAT_32\n');   
    fprintf(f,  '[Channel Infos]\n');
    for c=1:channels,
        if (finalChannelDigital) && (c == channels)
          fprintf(f, 'Ch%d=%d,,1,Digital\n',c,c);
        else
          fprintf(f, 'Ch%d=%d,,1,µV\n',c,c);
        end
    end %for each channel
    fclose(f);
    %next: write data file
    if (prevSamples > 0) %append
        f = fopen(dataFilename,'a','ieee-le'); %overwrite existing header
    else
        f = fopen(dataFilename,'w','ieee-le'); %overwrite existing header
    end;
    if VECTORIZED 
        fwrite(f, data', 'single'); %precision must match header "BinaryFormat"
    else
        fwrite(f, data, 'single'); %precision must match header "BinaryFormat"
    end
    fclose(f);
  %end % saveBrainVisionSub()



