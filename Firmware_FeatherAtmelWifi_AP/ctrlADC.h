/*
 * 
 * Functions to setup and read from the ADC inputs.
*/

#ifndef CTRL_ADC_H
#define CTRL_ADC_H

#include <Arduino.h>
#include <WiFi101.h>
#include <WiFiUdp.h>

// ADC defines
#define REF_PIN A0                // Name of the ADC input to use for reference (ADC in differential mode)
#define N_ADC_INPUT 5             // Number of ADC inputs
#define N_ADC_BUFFERS 64          // Number of ADC buffers
#define N_ADC_BUFFER_POS 16       // Number of positions in each buffer

// Global variables
extern uint8_t ADC_EnabledInputs; // Enabled ADC inputs
extern uint8_t iBufferTransmit;   // Buffer number to transmit to the remote UDP client (no transmit = 0xff)
extern uint8_t ADC_Gain;          // Gain setting the PGA before to the ADC.

void InitADC();                   // Initialize the ADC (change apropritate registers)
void ADC_StartRead();             // Start a new interupt based ADC reading.
void ADC_UpdateBufferIdx();       // Update the buffer indexes.
bool ADC_setGain(uint8_t Gain);   // Set the gain of the PGA before to the ADC.
// Transmit data to the remote UDP client.
void ADC_UdpTransmit(WiFiUDP UDP_in, uint8_t iBuffer_in, IPAddress IP_in, uint16_t Port_in);
void ADC_UdpTransmit(WiFiUDP UDP_in, uint8_t iBuffer_in, IPAddress IP_in, uint16_t Port_in, char DataType);

#endif /* CTRL_ADC_H */
