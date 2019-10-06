/*
 * 
 * Functions to setup and read from the ADC inputs.
*/


#include "ctrlADC.h"

uint8_t ADC_EnabledInputs = 0x00;     // Enabled ADC inputs
int16_t ADC_buffer[N_ADC_INPUT][N_ADC_BUFFERS][N_ADC_BUFFER_POS]; // ADC buffer
uint8_t iBuffer = 0;                  // Biffer index
int iBufferPos = 0;                   // Buffer position index
uint8_t iBufferTransmit = 0xff;       // Buffer number to transmit to the remote UDP client (no transmit = 0xff)
int iReadInput = -1;                  // ADC input index to read.
const uint8_t regInputs[] = {A1, A2, A3, A4, A5}; // MUX regsiter values for the ADC inputs
uint8_t ADC_Gain = 1;                 // Gain setting the PGA before to the ADC.

// Start a new interupt based ADC reading.
void ADC_StartRead()
{
  for (int iInput=iReadInput+1; iInput < N_ADC_INPUT; iInput++)
  {
    if (ADC_EnabledInputs & (1 << iInput))
    {      
      // Change the positive input MUX register
      ADC->INPUTCTRL.bit.MUXPOS = g_APinDescription[regInputs[iInput]].ulADCChannelNumber;
      while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

      ADC->SWTRIG.bit.FLUSH = 0x1;        // Flush ADC memory
      while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

      ADC->SWTRIG.bit.START = 0x1;        // Start the ADC reading
      while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

      // Save the index of input, that is current being read.
      iReadInput = iInput;

      // Break the for loop
      break;
    }
  }
}

// Transmit data to the remote UDP client.
void ADC_UdpTransmit(WiFiUDP UDP_in, uint8_t iBuffer_in, IPAddress IP_in, uint16_t Port_in){
  ADC_UdpTransmit(UDP_in, iBuffer_in, IP_in, Port_in, 'D');
}

// Transmit data to the remote UDP client.
void ADC_UdpTransmit(WiFiUDP UDP_in, uint8_t iBuffer_in, IPAddress IP_in, uint16_t Port_in, char DataType) {
  UDP_in.beginPacket(IP_in, Port_in);
  UDP_in.write((uint8_t)DataType);
  UDP_in.write(iBuffer_in);
  UDP_in.write(ADC_EnabledInputs);
  for (int iInput=0; iInput < N_ADC_INPUT; iInput++)
  {
    if (ADC_EnabledInputs & (0x1 << iInput))
    {
      for (int iPos=0; iPos < N_ADC_BUFFER_POS; iPos++)
      {
        UDP_in.write((uint8_t)ADC_buffer[iInput][iBuffer_in][iPos]);        // Write LSB (byte)
        UDP_in.write((uint8_t)(ADC_buffer[iInput][iBuffer_in][iPos] >> 8)); // Write MSB (byte)
      }
    }
  }
  UDP_in.endPacket();
}

// Update the buffer indexes.
void ADC_UpdateBufferIdx(){
  if (ADC_EnabledInputs) // Only update if an ADC input is enabled
  {
    iBufferPos++;
    if (iBufferPos == N_ADC_BUFFER_POS)
    {
      iBufferTransmit = iBuffer;  // Initiate new UDP transmit
      iBuffer++;
      iBuffer = iBuffer % N_ADC_BUFFERS;
      iBufferPos = 0;
    }
    iReadInput = -1;  
  }
}

// Set the gain of the PGA before to the ADC.
bool ADC_setGain(uint8_t Gain_in) {
  // Set the gain (ensure that the gain setting is valid, and return 'false' if not).
  switch (Gain_in)
  {
    case 1:
      ADC->INPUTCTRL.bit.GAIN = ADC_INPUTCTRL_GAIN_1X_Val;
      break;
    
    case 2:
      ADC->INPUTCTRL.bit.GAIN = ADC_INPUTCTRL_GAIN_2X_Val;
      break;

    case 4:
      ADC->INPUTCTRL.bit.GAIN = ADC_INPUTCTRL_GAIN_4X_Val;
      break;

    case 8:
      ADC->INPUTCTRL.bit.GAIN = ADC_INPUTCTRL_GAIN_8X_Val;            
      break;
      
    case 16:
      ADC->INPUTCTRL.bit.GAIN = ADC_INPUTCTRL_GAIN_16X_Val;
      break;

    default:
      return(false);
  }
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch
  ADC_Gain = Gain_in;
  return(true);
}

// ADC data interupt handler
void ADC_Handler() {
  // Read ADC result
  uint16_t sample = ADC->RESULT.reg;
  
  // Convert from 12 bit to 16 bit 2-complement representation  
  if (sample & 0x0800) {
    sample |= 0xf000;
  }
  ADC_buffer[iReadInput][iBuffer][iBufferPos] = (int16_t) sample;

  ADC_StartRead();
  
  // Clear the interupt flag
  //ADC->INTFLAG.bit.RESRDY = 0x1; // Interrupt Flag Status and Clear - Result Ready - cleared when RESULT i read.
}

// Initialize the ADC (change apropritate registers)
void InitADC() {
  // Select internal reference voltage for the ADC
  ADC->REFCTRL.bit.REFSEL = ADC_REFCTRL_REFSEL_INTVCC1_Val;
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

  // Set the ADC resolution to 12bit
  ADC->CTRLB.bit.RESSEL = ADC_CTRLB_RESSEL_12BIT_Val;
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

  // Set clock divider - determine the speed of convertion.
  ADC->CTRLB.bit.PRESCALER = ADC_CTRLB_PRESCALER_DIV64_Val;
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

  ADC->AVGCTRL.bit.SAMPLENUM = 0x0;   // Number of Samples to be Collected (0x00 = 1)
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

  // Set the negative (reference) input MUX register
  ADC->INPUTCTRL.bit.MUXNEG = g_APinDescription[REF_PIN].ulADCChannelNumber;
  while (ADC->STATUS.bit.SYNCBUSY) ; // Wait for clock domain sysch

  // Set the positive input MUX register
  ADC->INPUTCTRL.bit.MUXPOS = g_APinDescription[regInputs[0]].ulADCChannelNumber;
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

  ADC_setGain(1);                     // Set Gain

  ADC->CTRLB.bit.LEFTADJ  = 0x0;      // Left adjusted Result register
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch
 
  ADC->CTRLB.bit.DIFFMODE = 0x1;      // Set diffential mode
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch
  
  ADC->CTRLB.bit.FREERUN = 0x0;       // Set single convertion mode
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

  ADC->CTRLA.bit.ENABLE = 0x1;        // Enable the ADC
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

  ADC->INTENSET.bit.RESRDY = 0x1;     // Activate result ready interupt
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch

  ADC->INTFLAG.bit.RESRDY = 0x1;      // Clear ready flag
  while (ADC->STATUS.bit.SYNCBUSY) ;  // Wait for clock domain sysch  

  NVIC_EnableIRQ(ADC_IRQn);           // Register interupt function
}
