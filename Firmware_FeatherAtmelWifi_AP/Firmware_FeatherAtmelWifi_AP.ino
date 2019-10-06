/*
 * Firmware for transmitting ADC readings to a remote UDP client.
 * 
 * >>Protocol<<
 *   'S'  .........  Write status to remove UDP client
 *                   Status format: S[Samplerate_LSB][Samplerate_MSB][ADCgain][nADCinputs][nADCbuffers][nADCbufferPos_LSB][nADCbufferPos_MSB][EnabledADCinputs]
 *   'Axy'  .......  'y'='1': Enable analog input 'x', 'y'='0': Disable analog input 'x' [x-format: char, y-format: char]
 *   'Gx'  ........  Set gain of the PGA, located before the ADC (ADCgain), to 'x' [x-format: uint8_t].
 *   'Tx'  ........  Retransmit buffer index number 'x' [x-format: uint8_t].
 *   
 * >>Notes<<
 * - To compile the project, the following is needed
 *   1) Add the Adafruit Feather boards to the Boards Manager (Tools->Boards->Boards Manager). 
 *      - Detailed description is availible here: https://learn.adafruit.com/adafruit-feather-32u4-bluefruit-le/using-with-arduino-ide
 *   2) Install the wifi101 library using the Library Manager (Sketch->Include Libraru->Manage Libraries). 
 *      - Detailed description is availible here: https://learn.adafruit.com/adafruit-feather-m0-wifi-atwinc1500/using-the-wifi-module
*/

// >> Settings <<
#define SAMPLE_RATE 256           // ADC samplerate
#define UDP_PORT    62301         // UDP port number
#define AP_SSID     "FeatherSLK"    // Access point SSID (name)
#define AP_PASS     "FeatherBoardSLK" // Access point Password (must be 10 characters or more.)

// Includes
#include <SPI.h>
#include <WiFi101.h>
#include <WiFiUdp.h>

#include "ctrlTimer.h"
#include "ctrlADC.h"

// >> Variables <<
// WiFi AP settings
const char ssid[] = AP_SSID;
const char pass[] = AP_PASS;
int status = WL_IDLE_STATUS;      // WiFi connection status

//The udp library class
WiFiUDP udp;                      // UDP object

// UDP variables
IPAddress remoteIP;               // Remote UDP client IP
uint16_t remotePort = 0;          // Remote UDP client port number

// Buffers
char readBuffer[255];             // Buffer to hold incoming packet
char strError[256];               // Buffer to hold error messages


void setup() { 
  // Set the pins where the Wifi board is conected.
  WiFi.setPins(8,7,4,2);
  
  //Initialize serial and wait for port to open:
  Serial.begin(9600);
  /*while (!Serial) {
    ; // wait for serial port to connect. Needed for native USB port only
  }*/

  // check for the presence of the shield:
  if (WiFi.status() == WL_NO_SHIELD) {
    Serial.println("WiFi shield not present");
    // don't continue
    while (true);
  }

  // by default the local IP address of will be 192.168.1.1
  // you can override it with the following:
  // WiFi.config(IPAddress(10, 0, 0, 1));

  // Create open network. Change this line if you want to create an WEP network:
  status = WiFi.beginAP(ssid, pass);
  if (status != WL_AP_LISTENING) {
    Serial.println("Creating access point failed");
    // don't continue
    while (true);
  }

  // print the network SSID and Password;
  Serial.print("Access point created\nSSDI: ");
  Serial.println(ssid);
  Serial.print("Password: ");
  Serial.println(pass);
  
  // print your WiFi shield's IP address:
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());
  
  // print the received signal strength:
  Serial.print("signal strength (RSSI):");
  Serial.print(WiFi.RSSI());
  Serial.println(" dBm");  

  //initializes the UDP
  //This initializes the transfer buffer
  udp.begin(UDP_PORT);

  // Initialize the ADC.
  InitADC();

  // Initialize the sample timer.
  startTimer(SAMPLE_RATE);
}


void loop() {
  // Compare the previous status to the current status
  if (status != WiFi.status()) 
  {
    // The WiFi status has changed, update status variable and print the new status.
    status = WiFi.status();
    printWiFiStatus(status);
  }

  // Transmit ADC data
  if (iBufferTransmit < 0xff)
  {
    ADC_UdpTransmit(udp, iBufferTransmit, remoteIP, remotePort);
    iBufferTransmit = 0xff;
  }

  // if there's data available, read a packet
  int packetSize = udp.parsePacket();
  if (packetSize) {
    // Stoe the IP and Port number of the remote UDP client
    remoteIP = udp.remoteIP();
    remotePort = udp.remotePort();
    
    // Read the packet into the readBuffer
    int len = udp.read(readBuffer, 255);
    if (len > 0) {
      readBuffer[len] = 0; // Terminale the string
    }

    // Display received data on the serial port.
    sprintf(strError, "Received: data='%s', size=%i, port=%i, IP=", readBuffer, packetSize, remotePort);
    Serial.print(strError);
    Serial.println(remoteIP);

    strError[0] = 0; // Set Error to 0
    switch (readBuffer[0])
    {
      
      // Start/Stop sending data from the on the analog inputs
      case 'A':
        if (readBuffer[1] >= '1' && readBuffer[1] < N_ADC_INPUT+'1')
        {
          if (readBuffer[2] == '1' || readBuffer[2] == 0)
          {
            ADC_EnabledInputs |= 0x01 << readBuffer[1]-'1';
          }
          else
          {
            ADC_EnabledInputs  &= ~((uint8_t)0x01 << readBuffer[1]-'1');
          }
        }
        else if (readBuffer[1] == '0')
        {
          ADC_EnabledInputs = 0x00;
          UDP_TransmitStatus();
        }
        else
        {
          sprintf(strError, "E%c%c%c", readBuffer[0], readBuffer[1], readBuffer[2]);
        }
        break;

      // Transmit status
      case 'S':
         UDP_TransmitStatus();
         break; 
        
      // Retransmit data from buffer
      case 'T':
        if (readBuffer[1] < N_ADC_BUFFERS)
        {
          ADC_UdpTransmit(udp, (uint8_t)readBuffer[1], remoteIP, remotePort, 'T');
        }
        else
        {
          sprintf(strError, "E%c%c", readBuffer[0], readBuffer[1]);
        }
        break;

      // Change the ADC gain
      case 'G':
        if (ADC_setGain(readBuffer[1]))
        {
          UDP_TransmitStatus();
        }
        else
        {
          sprintf(strError,"EG%c",readBuffer[1]);
        }
        break;

      // Command not recognized
      default:
        sprintf(strError, "E%s", readBuffer);
        break;
    }

    // Write the error.
    if (strError[0] > 0)
    {
      // send a reply, to the IP address and port that sent us the packet we received
      udp.beginPacket(remoteIP, remotePort);
      udp.write(strError);
      udp.endPacket();
    }
  }
}

// Transmit status information to the remote UDP client.
void UDP_TransmitStatus() {  
  udp.beginPacket(remoteIP, remotePort);
  udp.write('S');
  udp.write((uint8_t)SAMPLE_RATE);
  udp.write((uint8_t)(SAMPLE_RATE >> 8));
  udp.write(ADC_Gain);
  udp.write((uint8_t)N_ADC_INPUT);
  udp.write((uint8_t)N_ADC_BUFFERS);
  udp.write((uint8_t)N_ADC_BUFFER_POS);
  udp.write((uint8_t)(N_ADC_BUFFER_POS >> 8));
  udp.write(ADC_EnabledInputs);
  udp.endPacket();
}

// Print Wifi Status to the Serial interface.
void printWiFiStatus(int status_in) {
    if (status_in == WL_AP_CONNECTED) {
      byte remoteMac[6];

      // A device has connected to the AP
      Serial.print("Device connected to AP, MAC address: ");
      WiFi.APClientMacAddress(remoteMac);
      Serial.print(remoteMac[5], HEX);
      Serial.print(":");
      Serial.print(remoteMac[4], HEX);
      Serial.print(":");
      Serial.print(remoteMac[3], HEX);
      Serial.print(":");
      Serial.print(remoteMac[2], HEX);
      Serial.print(":");
      Serial.print(remoteMac[1], HEX);
      Serial.print(":");
      Serial.println(remoteMac[0], HEX);
    } else {
      // A device has disconnected from the AP, and we are back in listening mode
      Serial.println("Device disconnected from AP");
    }
}
