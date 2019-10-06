
%
% >>Description<<
% Example of how to use the WiFiUDPlogger class to receive data from an Adafruit Feather board.
%

obj = WiFiUDPlogger;
obj = open(obj);
if obj.Connected
    obj = recordData(obj,1);
    plot(obj);
end
obj = close(obj);