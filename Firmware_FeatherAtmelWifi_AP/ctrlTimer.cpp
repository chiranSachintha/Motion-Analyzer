/*
 * 
 * Functions to setup of the ADC sample timer.
*/

#include "ctrlTimer.h" 
#include "ctrlADC.h"

TcCount16* TC = (TcCount16*) TC3;   // Timer object (e.g. TC3)

// Timer interupt handler
void TC3_Handler() {
  // If this interrupt is due to the compare register matching the timer count
  if (TC->INTFLAG.bit.MC0 == 1) 
  {
    // Clear interupt flag
    TC->INTFLAG.bit.MC0 = 1;

    // Start a new ADC read
    ADC_UpdateBufferIdx();
    ADC_StartRead();
  }
}

// Change the timer frequency
void setTimerFrequency(int frequencyHz) {
  // Calculate new timer compare value
  int compareValue = (CPU_HZ / (TIMER_PRESCALER_DIV * frequencyHz)) - 1;
  
  // Make sure the count is in a proportional position to where it was
  // to prevent any jitter or disconnect when changing the compare value.
  TC->COUNT.reg = map(TC->COUNT.reg, 0, TC->CC[0].reg, 0, compareValue);
  
  // Set counter compare register
  TC->CC[0].reg = compareValue;
  while (TC->STATUS.bit.SYNCBUSY == 1); // Wait for clock domain sysch
}

// Setup and start the timer.
void startTimer(int frequencyHz) {
  REG_GCLK_CLKCTRL = (uint16_t) (GCLK_CLKCTRL_CLKEN | GCLK_CLKCTRL_GEN_GCLK0 | GCLK_CLKCTRL_ID_TCC2_TC3) ;
  while ( GCLK->STATUS.bit.SYNCBUSY); // Wait for clock domain sysch

  // Enable the timer
  TC->CTRLA.reg &= ~TC_CTRLA_ENABLE;
  while (TC->STATUS.bit.SYNCBUSY);    // Wait for clock domain sysch

  // Use the 16-bit timer
  TC->CTRLA.reg |= TC_CTRLA_MODE_COUNT16;
  while (TC->STATUS.bit.SYNCBUSY);    // Wait for clock domain sysch

  // Use match mode so that the timer counter resets when the count matches the compare register
  TC->CTRLA.reg |= TC_CTRLA_WAVEGEN_MFRQ;
  while (TC->STATUS.bit.SYNCBUSY);    // Wait for clock domain sysch

  // Set prescaler to 1024
  TC->CTRLA.reg |= TC_CTRLA_PRESCALER_DIV1024;
  while (TC->STATUS.bit.SYNCBUSY);    // Wait for clock domain sysch

  // Set timer frequency
  setTimerFrequency(frequencyHz);

  // Enable the compare interrupt
  TC->INTENSET.reg = 0;
  TC->INTENSET.bit.MC0 = 1;

  // Register interupt function
  NVIC_EnableIRQ(TC3_IRQn);

  // Enable the timer
  TC->CTRLA.reg |= TC_CTRLA_ENABLE;
  while (TC->STATUS.bit.SYNCBUSY);    // Wait for clock domain sysch
}
