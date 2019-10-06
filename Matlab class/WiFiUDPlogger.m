% >>Description<<
% Class which enables the user to open and close a UDP connection, and received data from a Arduino Feather board running appropriate firmware.
%
% >>Properties<<
%   Data:               ADC readings [size: nInputs x nSamples, unit: Volt, type: double]
%   Recordings:         Struct containing previous recordings performed with the same class object.
%   labelADCinput:      ADC input labels [size: nInputs x 1, type: cell array of strings]
%
%  >UDP connection settings
%   RemoteHostIP:       IP address of the remote host
%   RemoteHostPort:     Port number for the UDP connection
%   InputBufferSize:    Buffer size for the UDP object.
%   Connected:          true: Connected to the Arduino Feather board.
%
%  >ADC settings
%   ADCsamplerate:      Samplerate of the ADC
%   ADCgain:            Gain setting the PGA before to the ADC.
%
%  >Live plot settings
%   LivePlotEnabled:    true: Plot live data during recording
%   LiveWindowSize:     Windows size of the live plot [unit: seconds]
%   freqBandpass:       Corner frequencies for the bandpass filter [unit: Hz, size:1x2]
%   freqNotch:          Notch filter frequencies [Unit:Hz]
%   bandwidthNotch:     Width of notch filter [unit:Hz]
%
% >>Functions<<
%   obj = open(obj)  .............................  Open UDP connection.
%   obj = close(obj) .............................  Close UDP connection.
%   obj = setADCgain(obj, gain)  .................  Set the gain of the PGA before to the ADC.
%   obj = clearData(obj)  ........................  Clear the obj.Data to initialize a new recording.
%   obj = recordData(obj, iInputs, RecordTime)  ..  Record data from the ADCs (parameters 'iInputs' and 'RecordTime' are optional).
%   handle = plot(obj)  ..........................  Plot data.
%   [obj, nRecvDataPackets] = readData(obj)  .....  Read availible data from the UDP object.
%   [obj, hFig] = plotLive(obj, RecordTime)  .....  Create a GUI for live plotting (parameter 'RecordTime' is optional).
%
% >>Example<<
%   obj = WiFiUDPlogger;
%   obj = open(obj);
%   if obj.Connected
%       obj = recordData(obj);
%       plot(obj);
%   end
%   obj = close(obj);

classdef WiFiUDPlogger
    properties
        Data = [];
        Recordings = [];
        labelADCinput = {};
        
        % UDP connection settings.
        RemoteHostIP = '192.168.1.1';
        RemoteHostPort = 62301;
        InputBufferSize = 1e6;
        Connected = false;
        
        % ADC settings
        ADCsamplerate = [];
        ADCgain = [];
        
        % Live plot settings
        LivePlotEnabled = true;
        LiveWindowSize = 5;
        freqBandpass = [0.1 45];
        freqNotch = [50 100];
        bandwidthNotch = 0.5;
    end
    
    properties (SetAccess = private, Hidden = true)
        hUDP = [];                  % UDP object
        
        iData = 1;                  % Data struct index
        iBufferLast = [];           % Last received ADC buffer index
        
        % ADC settings
        ADCscale = 3.3/2^12;        % ADC scaling factor        
        nADCinput = [];             % Number of ADC inputs
        nADCbuffers = [];           % Number of ADC buffers
        nADCbufferPos = [];         % Number of positions in each buffer
        mEnabledInputs= [];         % Enabled ADC inputs
        
        % Live plot settings
        TimeAxis = [];        
        AddLiveBuffer = 2;          % Seconds to add to live windows (this is relavant to avoid e.g. filter transient effects)
        LiveYlims = [-0.5 0.5]*3.3; % Ylimits of the Live plot
        GridLines = true;           % Activate grid lines
        thdSaturation = [];         % Saturation threshold [unit: Volt]
        GainOptions = [1 2 4 8 16]; % Availible gain options
        widthUserInputs = 0.1;      % The width of the UI elements to the right of the live plot
        heightUserInputs = 0.035;   % The height of the UI elements to the right of the live plot
        distUserInputs = 0.01;      % The distance between the UI elements to the right of the live plot
        dispRetransmit = false;     % true: Display retransmit commands in the command window.
    end
    
    methods
        
        %% Open UDP connection
        function obj = open(obj)
            obj.hUDP = udp(obj.RemoteHostIP, obj.RemoteHostPort, 'InputBufferSize',obj.InputBufferSize);
            fopen(obj.hUDP);
            
            % Try to connect to the host 5 times and display an error if it fails.
            for idx=1:20
                fprintf(obj.hUDP,'S');
                
                % Wait for response
                pause(0.1);
                obj = readData(obj);
                if obj.Connected
                    obj.Data = nan(obj.nADCinput, 1);
                    obj.TimeAxis = 0;
                    obj.iBufferLast = [];
                    break;
                end
            end
            if ~obj.Connected
                obj = close(obj);
                errordlg(sprintf('Could not connect to remote host\n IP:%s, Port:%i', obj.RemoteHostIP, obj.RemoteHostPort));
            end
            
        end
        
        %% Close UDP connection
        function obj = close(obj)
            if obj.Connected
                % Send command to stop transmitting of ADC readings.
                fprintf(obj.hUDP,'A0');
            end
            pause(0.01);
            try
                fclose(obj.hUDP);
            catch
            end
            delete(obj.hUDP);
            obj.Connected = false;
        end
        
        %% Set the gain of the PGA before to the ADC.
        function obj = setADCgain(obj, gain)
            if obj.Connected
                fprintf(obj.hUDP,'G%s',gain);
                pause(0.02);
                obj = readData(obj);
            end
        end
        
        %% Clear the obj.Data to initialize a new recording.
        function obj = clearData(obj)
            obj = readData(obj);
            obj.Data = nan(obj.nADCinput, 1);
            obj.TimeAxis = 0;
            obj.iBufferLast = [];
            obj.iData = 1;
        end
        
        %% Record data from the ADCs (parameters 'iInputs' and 'RecordTime' are optional)
        function obj = recordData(obj, iInputs, RecordTime)
            if nargin < 2
                iInputs = [];
            end
            if nargin < 3
                RecordTime = 0;
            end
            
            if obj.Connected   
                % Clear the data array to before starting af new recording
                obj = clearData(obj);                                
                
                % Send commands to start transmitting of ADC readings.
                for idx = iInputs
                    fprintf(obj.hUDP,'A%i1',idx);
                end
                
                % If no input indexes are given, ask for a status from the board
                if isempty(iInputs)
                    fprintf(obj.hUDP,'S');
                end
                
                if obj.LivePlotEnabled
                    obj = plotLive(obj, RecordTime);
                else
                    % Create message box, which enable the user to stop the recording
                    hRec = msgbox('Recording running');
                    hRec.Children(1).String = 'Stop recording';
                    hRec.Children(1).Position = hRec.Children(1).Position + [-20 0 40 0];
                    
                    % Start the recording
                    tic
                    iSec = 1;
                    while ishandle(hRec) && (isempty(RecordTime) || RecordTime <= 0  || toc < RecordTime)
                        obj = readData(obj);
                        if toc >= iSec
                            fprintf('Recording %i of %i seconds\n', iSec, RecordTime);
                            iSec = iSec + 1;
                        end
                        pause(0.01);
                    end
                end
                
                % Send command to stop transmitting of ADC readings.
                fprintf(obj.hUDP,'A0');
                obj.mEnabledInputs(:) = 0;
                
                % Store the recorded data in the obj.Data array to obj.Recordings
                if size(obj.Data,2) > 1
                    obj.Recordings(end+1).Data = obj.Data;
                    obj.Recordings(end).TimeAxis = obj.TimeAxis;
                end
            else
                errordlg('You must open the UDP connection before recording data');
            end
        end
        
        %% Plot data (obj.Data)
        function handle = plot(obj)
            handle = plot(obj.TimeAxis,obj.Data');
            xlim([obj.TimeAxis(1) obj.TimeAxis(end)]);
            xlabel('time [sec.]');
            ylabel('Amplitude [V]');
        end                
        
        %% Read availible data from the UDP object.
        function [obj, nRecvDataPackets] = readData(obj)
            nRecvDataPackets = 0;
            while obj.hUDP.BytesAvailable > 0
                RecvData = fread(obj.hUDP, obj.hUDP.BytesAvailable);
                
                switch RecvData(1)
                    
                        % Status received
                    case 'S'
                        obj.ADCsamplerate = RecvData(2) + 256*RecvData(3);
                        obj.ADCgain = RecvData(4);
                        obj.nADCinput = RecvData(5);
                        obj.nADCbuffers = RecvData(6);
                        obj.nADCbufferPos = RecvData(7) + 256*RecvData(8);
                        obj.mEnabledInputs = bitget(RecvData(9),1:obj.nADCinput) == 1;
                        obj.Connected = true;
                        
                        % update active inputs
                        if length(obj.mEnabledInputs) ~= obj.nADCinput
                            fprintf(obj.hUDP,'A0');
                            obj.mEnabledInputs= zeros(1,obj.nADCinput);
                        end
                        
                        % Update yLimits of the Live plot
                        obj.LiveYlims = [-0.5 0.5]*3.3/obj.ADCgain;
                        obj.thdSaturation = obj.LiveYlims(2)*0.99;
                        
                        % Update channel labels
                        if isempty(obj.labelADCinput) || length(obj.labelADCinput) < obj.nADCinput
                            for iLabel =  length(obj.labelADCinput)+1 :obj.nADCinput
                                obj.labelADCinput{iLabel} = sprintf('A%i',iLabel);
                            end
                        end
                        
                        % Data received
                    case {'D','T'}
                        iBuffer = RecvData(2);
                        obj.mEnabledInputs = bitget(RecvData(3),1:obj.nADCinput) == 1;
                        iEnabledInputs= find(obj.mEnabledInputs);
                        
                        if RecvData(1) == 'D' % Received 'ordinary' data
                            if isempty(obj.iBufferLast)
                                obj.iBufferLast = iBuffer - 1;
                            end
                            
                            % Locate missing UDP packets
                            if iBuffer > obj.iBufferLast
                                iMissing = obj.iBufferLast+1:iBuffer-1;
                            else
                                iMissing = obj.iBufferLast+1:obj.nADCbuffers-1;
                                iMissing = [iMissing 0:iBuffer-1];
                            end
                            
                            % Ask for retransmit of missing UDP packets
                            for iBuf = iMissing
                                fprintf(obj.hUDP,'T%s', iBuf);
                                if obj.dispRetransmit
                                    fprintf('Send retransmit, iBuffer=%i\n',iBuf);
                                end
                            end
                            
                            % Update indexes
                            obj.iData = obj.iData + 1 + length(iMissing);
                            obj.iBufferLast = iBuffer;
                            iDataWrite = obj.iData;
                        else % Received retransmitted data
                            if iBuffer < obj.iBufferLast
                                iDataWrite = obj.iData - (obj.iBufferLast - iBuffer);
                            else
                                iDataWrite = obj.iData - (obj.iBufferLast + (obj.nADCbuffers-iBuffer) );
                            end
                            if obj.dispRetransmit
                                fprintf('Recv retransmit, iBuffer=%i\n', iBuffer);
                            end
                        end
                        
                        % Store the received data in the obj.Data array and obj.TimeAxis.
                        if iDataWrite > 0
                            iRecvData = 4;
                            iRange = (1:obj.nADCbufferPos)+(iDataWrite-1)*obj.nADCbufferPos;
                            for iInput = 1:length(iEnabledInputs)
                                for iBufferPos = 1:obj.nADCbufferPos
                                    Sample = RecvData(iRecvData) + RecvData(iRecvData+1)*2^8;
                                    if Sample > 2^15 % data with negative sign (2-complement format)
                                        Sample = Sample - 2^16;
                                    end
                                    Sample = Sample * obj.ADCscale / obj.ADCgain;
                                    obj.Data(iEnabledInputs(iInput),iRange(iBufferPos)) = Sample;
                                    iRecvData = iRecvData + 2;
                                end
                            end
                            obj.Data(~obj.mEnabledInputs,iRange) = NaN;
                            obj.TimeAxis = (0:size(obj.Data,2)-1)/obj.ADCsamplerate;
                        end
                        nRecvDataPackets = nRecvDataPackets + 1;
                        
                        % Error received
                    case 'E'
                        warning('Error: %s',RecvData);                        
                        
                    otherwise
                        warning('Command ''%s'' not recognized - ignoring the UDP packet.', RecvData(1));
                        
                end
            end
        end
        
        %% Create a GUI for live plotting
        function [obj, hFig] = plotLive(obj, RecordTime)
            if obj.Connected                
                %% initiate variables
                Saturation = ones(obj.nADCinput,1)*2;
                LoadBuffer = false;
                UpdatePlot = true;
                mEnabledInputsLast = zeros(1,obj.nADCinput);
                
                nLiveWindowSize = obj.LiveWindowSize * obj.ADCsamplerate;
                nLiveBuffer = nLiveWindowSize + obj.AddLiveBuffer*obj.ADCsamplerate;
                
                mLiveInputs = obj.mEnabledInputs;
                iLiveInputs = find(mLiveInputs == 1);     
                
                colorSat = [0 200 0; 200 0 0];
                strOnOff = {'off','on'};
                newGain = [];                
                
                if nargin < 2 || isempty(RecordTime)
                    RecordTime = 0;
                end                
                
                %% Create the liveplot figure
                hFig = figure('name',sprintf('ADC stream'));
                hFig.Position = [100 100 1000 600];
                hAxis = gca;
                hLines = line(nan(2,obj.nADCinput),nan(2,obj.nADCinput));
                
                xlabel(hAxis,'Time [sec]');
                ylabel(hAxis,'Amplitude [V]');
                ylim(hAxis, obj.LiveYlims);
                
                legend(obj.labelADCinput)
                
                % Resize axis and add controls to the right in the figure
                set(hAxis,'position',get(hAxis,'Position') - [0.07 0 obj.widthUserInputs-0.07 0])
                posAxis = get(hAxis,'Position');
                
                posUIcontrols = [posAxis(1)+posAxis(3)+0.01 posAxis(2)+posAxis(4) obj.widthUserInputs+0.2 obj.heightUserInputs];
                
                %% Create UI element to the right in the figure
                
                % Add check boxes to activate/deactivate plotting of the ADC inputs
                posUIcontrols = posUIcontrols - [0 obj.heightUserInputs 0 0];
                hTxtInput = uicontrol(hFig,'Style','text','String','ADC inputs:','units','normalized', 'Position', posUIcontrols,'HorizontalAlignment','left');
                for iADCinput = 1:obj.nADCinput
                    posUIcontrols = posUIcontrols - [0 obj.heightUserInputs+obj.distUserInputs 0 0];
                    hChkInput(iADCinput) = uicontrol(hFig,'Style','checkbox','String',obj.labelADCinput{iADCinput},'units','normalized','Position',posUIcontrols);
                    set(hChkInput(iADCinput),'Value', obj.mEnabledInputs(iADCinput));
                end
                
                % Add 'properties' text string
                posUIcontrols = posUIcontrols - [0 obj.heightUserInputs+obj.distUserInputs*2 0 0];
                hTxtProps = uicontrol(hFig,'Style','text','String','Properties:','units','normalized', 'Position', posUIcontrols, 'HorizontalAlignment','left');
                
                % Add check box to activate/deactivate the grid lines
                posUIcontrols = posUIcontrols - [0 obj.heightUserInputs+obj.distUserInputs 0 0];
                hChkGrid = uicontrol(hFig,'Style','checkbox','String','Grid Lines','units','normalized','Position',posUIcontrols);
                hChkGrid.Value = obj.GridLines;
                grid(hAxis, strOnOff{obj.GridLines+1});
                
                % Add pop menu (drop-drown box) to select the ADC gain
                posUIcontrols = posUIcontrols - [0 obj.heightUserInputs+obj.distUserInputs 0 0];
                hTxtGain = uicontrol(hFig,'Style','text','String','Gain','units','normalized', 'Position', posUIcontrols - [0 0.008 0 0],'HorizontalAlignment','left');
                hPopGain = uicontrol(hFig,'Style','popupmenu','String',obj.GainOptions,'units','normalized','Position',posUIcontrols + [0.03 0 -0.25 0]);
                [~, hPopGain.Value] = ismember(obj.ADCgain, obj.GainOptions);
                
                % Add check box to activate/deactivate the notch filters
                if isempty(obj.freqNotch) == false
                    strNotch = sprintf('Notch (');
                    for iNotch = 1:length(obj.freqNotch)
                        strNotch = sprintf('%s%0.1f,',strNotch,obj.freqNotch(iNotch));
                    end
                    strNotch(end) = ')';
                    
                    posUIcontrols = posUIcontrols - [0 obj.heightUserInputs+obj.distUserInputs 0 0];
                    hChkNotch = uicontrol(hFig,'Style','checkbox','String', strNotch,'units','normalized','Position',posUIcontrols);
                    set(hChkNotch,'Value', false);
                end
                
                % Add check box to activate/deactivate the bandpass filter
                if isempty(obj.freqBandpass) == false
                    if length(obj.freqBandpass) == 1
                        strBandPass = sprintf('Highpass (%0.1f)',obj.freqBandpass);
                    elseif length(obj.freqBandpass) == 2
                        strBandPass = sprintf('Bandpass (%0.1f-%0.1f)',obj.freqBandpass(1),obj.freqBandpass(2));
                    end
                    posUIcontrols = posUIcontrols - [0 obj.heightUserInputs+obj.distUserInputs 0 0];
                    hChkBandpass = uicontrol(hFig,'Style','checkbox','String',strBandPass,'units','normalized','Position',posUIcontrols);
                    set(hChkBandpass,'Value', false);
                end
                
                % Add check box to activate/deactivate updating of the Plot
                posUIcontrols = posUIcontrols - [0 obj.heightUserInputs+obj.distUserInputs 0 0];
                hChkUpdateData = uicontrol(hFig,'Style','checkbox','String','Update plot','units','normalized','Position',posUIcontrols);
                hChkUpdateData.Value = true;
                
                % Add saturation image area
                posUIcontrols = posUIcontrols - [0 obj.heightUserInputs+obj.distUserInputs 0 0];
                hTxtSaturation = uicontrol(hFig,'Style','text','String','Saturation:','units','normalized', 'Position', posUIcontrols, 'HorizontalAlignment','left');
                
                posUIcontrols = posUIcontrols - [0 obj.heightUserInputs 0 0];
                hSatAxis = axes('position',[posUIcontrols(1) posUIcontrols(2) 0.10 posUIcontrols(4)]);
                hSatAxis.Visible = 'off';
                hSatImage = image(zeros(1,obj.nADCinput,3));
                hSatAxis.XTick = [];
                hSatAxis.YTick = [];
                for iADCinput = 1:obj.nADCinput
                    text(iADCinput,1,obj.labelADCinput{iADCinput},'HorizontalAlignment','center','VerticalAlignment','middle','FontSize',8,'Color','w','FontWeight','bold');
                end
                
                % Add check box to activate/deactivate to show buffered data.
                posUIcontrols = posUIcontrols - [0 obj.heightUserInputs*1.2+obj.distUserInputs 0 0];
                hChkLoadBuffer = uicontrol(hFig,'Style','checkbox','String','Load buffer','units','normalized','Position',posUIcontrols);
                hChkLoadBuffer.Value = false;
                
                % Prepare filters for live view
                bw = obj.bandwidthNotch/obj.ADCsamplerate*2;    % bandwidth of the notch filter (iirnotch)
                a_Notch = zeros(length(obj.freqNotch),3);
                b_Notch = zeros(length(obj.freqNotch),3);
                if isempty(which('iirnotch')) == false
                    for iNotch=1:length(obj.freqNotch)
                        [b_Notch(iNotch,:),a_Notch(iNotch,:)] = iirnotch(obj.freqNotch(iNotch)/obj.ADCsamplerate*2,bw);
                    end
                else
                    set(hChkNotch,'Visible','off','Value', false);
                end
                
                if isempty(which('butter')) == false
                    if length(obj.freqBandpass) == 1
                        [b_BandPass, a_BandPass] = butter(4,obj.freqBandpass/obj.ADCsamplerate*2,'high');
                    elseif length(obj.freqBandpass) == 2
                        [b_BandPass, a_BandPass] = butter(4,obj.freqBandpass/obj.ADCsamplerate*2);
                    end
                else
                    set(hChkBandpass,'Visible','off','Value', false);
                end
                
                
                %% Read and plot data
                tic
                iSec = 1;
                while (RecordTime <= 0  || toc < RecordTime) && ishandle(hFig)
                    
                    % Update record time
                    if RecordTime > 0 && toc >= iSec
                        fprintf('Recording %i of %i seconds\n', iSec, RecordTime);
                        iSec = iSec + 1;
                    end
                    
                    % Read data from the UDP object
                    [obj, nRecvDataPackets] = readData(obj);                    
                    
                    % If the figure is still open, handle update of a few UI elements
                    if ishandle(hFig)
                        % Handle update of plot checkboxes
                        if any(mLiveInputs ~= [hChkInput.Value])
                            for iInput = 1:obj.nADCinput
                                if mLiveInputs(iInput) ~= hChkInput(iInput).Value
                                    fprintf(obj.hUDP,sprintf('A%i%i',iInput,hChkInput(iInput).Value));
                                end
                            end
                            mLiveInputs = [hChkInput.Value];
                            iLiveInputs = find(mLiveInputs == 1);
                            UpdatePlot = true;
                        end
                        
                        % Update visibiliy of the plot lines
                        if any(obj.mEnabledInputs ~= mEnabledInputsLast)
                            for iInput = 1:obj.nADCinput
                                hLines(iInput).Visible = strOnOff{obj.mEnabledInputs(iInput)+1};
                                if mLiveInputs(iInput) ~= obj.mEnabledInputs(iInput)
                                    hChkInput(iInput).Value = obj.mEnabledInputs(iInput);
                                end
                                Saturation(iInput) = 2;
                            end
                        end
                        
                        % Handle changes in the gridline plotting
                        if hChkGrid.Value ~= obj.GridLines
                            obj.GridLines = hChkGrid.Value;
                            grid(hAxis, strOnOff{obj.GridLines+1});
                            UpdatePlot = true;
                        end
                        
                        % Gain settings changed by the user, transmit the new gain to the Adafruit Feather board.
                        if obj.ADCgain ~= obj.GainOptions(hPopGain.Value)
                            obj = setADCgain(obj, obj.GainOptions(hPopGain.Value));
                            newGain = obj.GainOptions(hPopGain.Value);
                        end
                        
                        % The ADC gain have been changed, update the y-limits
                        if obj.ADCgain == newGain
                            ylim(hAxis, obj.LiveYlims)
                            newGain = [];
                        end
                        
                    end                   
                    
                    % New data (obj.Data) have been received, plot the data.
                    if nRecvDataPackets > 0 && ishandle(hFig)
                        nData = size(obj.Data,2);
                        iLiveBuffer = max(nData-nLiveBuffer+1,1):nData;
                        iLiveWindow = max(length(iLiveBuffer)-nLiveWindowSize,1):length(iLiveBuffer);
                        
                        % Handle loading of the buffered data if the Load buffer checkbox i checked.
                        if hChkLoadBuffer.Value ~= LoadBuffer
                            if hChkLoadBuffer.Value
                                hChkUpdateData.Visible = 'off';
                                hChkUpdateData.Value = true;
                                iLiveBuffer = 1:nData;
                                iLiveWindow = 1:nData;
                            else
                                hChkUpdateData.Visible = 'on';
                            end
                            LoadBuffer = hChkLoadBuffer.Value;
                            UpdatePlot = true;
                        end
                        
                        % Plot the data
                        if hChkUpdateData.Value && UpdatePlot
                            if LoadBuffer
                                UpdatePlot = false;
                            end
                            
                            LiveBuffer = obj.Data(:,iLiveBuffer);
                            
                            % Check for saturation of the channels
                            CurrentSat = mLiveInputs' & (max(abs(LiveBuffer(:,iLiveWindow)),[],2) > obj.thdSaturation);
                            if any(CurrentSat ~= Saturation)
                                Saturation = CurrentSat;
                                SatImage = uint8(ones(size(Saturation,1),size(Saturation,2),3)*255);
                                for iInput = 1:obj.nADCinput
                                    SatImage(1,iInput,:) = uint8(colorSat(Saturation(iInput)+1,:));
                                end
                                hSatImage.CData = SatImage;
                            end
                            
                            % Apply notch filters
                            if exist('b_Notch','var') && hChkNotch.Value
                                LiveBuffer(isnan(LiveBuffer)) = 0;
                                for iNotch = 1:size(b_Notch,1)
                                    for iInput = iLiveInputs
                                        LiveBuffer(iInput,:) = filter(b_Notch(iNotch,:), a_Notch(iNotch,:), LiveBuffer(iInput,:));
                                    end
                                end
                            end
                            
                            % Apply bandpass filters
                            if exist('b_BandPass','var') && hChkBandpass.Value
                                LiveBuffer(isnan(LiveBuffer)) = 0;
                                for iInput = iLiveInputs
                                    LiveBuffer(iInput,:) = filter(b_BandPass, a_BandPass, LiveBuffer(iInput,:));
                                end
                            end
                            
                            % Update the plot
                            for iInput = 1:obj.nADCinput
                                set(hLines(iInput),'XData', obj.TimeAxis(iLiveBuffer(iLiveWindow)), 'YData', LiveBuffer(iInput,iLiveWindow));
                            end
                            
                            % Update xlimits
                            if LoadBuffer
                                xLims = obj.TimeAxis([1 end]);
                            else
                                if length(iLiveWindow) < nLiveWindowSize
                                    xLims = [(length(iLiveWindow)-nLiveWindowSize)/obj.ADCsamplerate obj.TimeAxis(iLiveBuffer(iLiveWindow(end)))];
                                else
                                    xLims = obj.TimeAxis(iLiveBuffer(iLiveWindow([1 end])));
                                end
                            end
                            xlim(hAxis, xLims);
                        end
                        mEnabledInputsLast = obj.mEnabledInputs;
                        drawnow;
                    else
                        pause(0.01);
                    end
                end
                fprintf('Total record time = %0.1f\n', toc);
            else
                warning('WiFiUDPlogger(): You must be connected to use the plotLive() function');
            end
        end
        
    end
end