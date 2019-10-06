/*
 * Created by: Simon Lind Kappel - simon@lkappel.dk - November 2017
 * 
 * Functions to setup of the ADC sample timer.
*/

#ifndef CTRL_TIMER_H
#define CTRL_TIMER_H

#include <Arduino.h>

#define TIMER_PRESCALER_DIV 1024          // Timer clock scaler.
#define CPU_HZ 48000000                   // CPU clock frequency

void setTimerFrequency(int frequencyHz);  // Change the timer frequency
void startTimer(int frequencyHz);         // Setup and start the timer.

#endif /* CTRL_TIMER_H */
