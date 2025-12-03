;
; trafficLightProject.asm
;
; Created: 11/29/2025 6:06:02 PM
; Author : Miguel Getzain Gomez, Richard Ortega, Cheleyson Dorvilien
; Desc   : Our code runs a fully automated traffic intersection that works like a real traffic light system.
It cycles through green, yellow, and red lights for both directions, and it safely handles pedestrians when they 
press the walk button. The timing of each light and walk signal is controlled using the microcontroller’s 
interrupts and a simple state machine. Overall, the project works by using basic microcontroller features such 
as GPIO pins, external interrupts, timers, and FSM logic.

; Declare constants and global variables
;------------------------------------------------------------------------------
.nolist
.include "m328pdef.inc"
.list
.equ TIMER_CONST = 6249                 ; Compare value for Timer1 to get 100ms tick 

; Pin Declarations: 
.equ NS_GRN = PB2                       ; North-South green LED pin 
.equ NS_YEL = PB3                       ; North-South yellow LED pin 
.equ NS_RED = PB4                       ; North-South red LED pin 
.equ NS_WLK = PB1                       ; North-South white walk LED pin 
.equ NS_DWK = PB0                       ; North-South red don't-walk LED pin 

; East/ West Pins
.equ EW_GRN = PC3                       ; East-West green LED pin 
.equ EW_YEL = PC2                       ; East-West yellow LED pin 
.equ EW_RED = PC1                       ; East-West red LED pin 
.equ EW_WLK = PC4                       ; East-West white walk LED pin 
.equ EW_DWK = PC5                       ; East-West red don't-walk LED pin 

; Buttons for the cross walk
.equ NS_BTN = PD2                       ; North-South walk button pin (INT0) 
.equ EW_BTN = PD3                       ; East-West walk button pin (INT1) 

; Vairables
.def temp = r16                         ; Temporary registers
.def tickFlag = r21                     ; Flag set every 100ms by timer ISR 
.def nsReq = r22                        ; N/S crosswalk request flag
.def ewReq = r23                        ; E/W crosswalf request flag

; --- SRAM VARIABLES (Manual Mapping) --- 
.equ state = 0x0100                     ; Current FSM state (0–5) 
.equ stateTimer = 0x0101                ; Counts ticks in the current state 
.equ walkTimer = 0x0102                 ; Counts ticks for walk/blink timing 

; Vector Table 
; ------------------------------------------------------------ 
.org 0x0000                             ; Reset vector address 
          jmp       main
.org INT0addr                           ; External Interrupt Request 0
          jmp       ns_btn_isr
.org INT1addr                           ; External Interrupt Request 1 
          jmp       ew_btn_isr
.org OC1Aaddr                           ; Timer/Counter1 Compare Match A 
          jmp       timer_isr
.org INT_VECTORS_SIZE                   ; End of interrupt vector table 

; one-time configuration 
; ------------------------------------------------------------ 
main: 
          ; Initialize GPIO
          ; North/South Lights
          ldi       r16, (1<<NS_GRN)|(1<<NS_YEL)|(1<<NS_RED)|(1<<NS_WLK)|(1<<NS_DWK)
          out       DDRB, r16                   ; Output mode for NS lights

          ; East/West Lights
          ldi       r16, (1<<EW_GRN)|(1<<EW_YEL)|(1<<EW_RED)|(1<<EW_WLK)|(1<<EW_DWK)
          out       DDRC, r16                   ; Output mode for EW lights

          ; setup NS button
          cbi       DDRD, NS_BTN                ; input(0) mode
          sbi       PORTD, NS_BTN               ; pull-up (1 = 5v)

          ; setup EW button
          cbi       DDRD, EW_BTN                ; input(0) mode
          sbi       PORTD, EW_BTN               ; pull-up (1 = 5v)

          ; Setup Interrupts
          sbi       EIMSK, INT0                 ; External interrupt 0 
          sbi       EIMSK, INT1                 ; External interrupt 1 

          ; Trigger on Falling Edge (10) for buttons 
          ldi       r16, (1 << ISC11) | (1 << ISC01) 
                                      ; INT1 falling edge, INT0 falling edge 
          sts       EICRA, r16        ; Store into External Interrupt Control Register A 

          ; --- SETUP TIMER1 (100ms) --- 
          clr       r20               ; Clear r20 
          sts       TCCR1A, r20       ; Normal operation, no outputs used 

          ldi       r20, high(TIMER_CONST) ; Load high byte of compare value 
          sts       OCR1AH, r20       ; Set OCR1A high 
          ldi       r20, low(TIMER_CONST)  ; Load low byte 
          sts       OCR1AL, r20       ; Set OCR1A low 

          ldi       r20, (1 << WGM12) | (1 << CS12) 
                                      ; CTC mode, prescaler 256 
          sts       TCCR1B, r20       ; Start Timer1 

          ldi       r20, (1 << OCIE1A); Enable Timer1 Compare A interrupt 
          sts       TIMSK1, r20       ; Enable in timer interrupt mask register 

          ; --- INIT VARIABLES --- 
          clr       r16               ; r16 = 0 
          sts       state, r16        ; Start in state 0 (NS Green) 
          sts       stateTimer, r16   ; Clear state timer 
          sts       walkTimer, r16    ; Clear walk timer 
          clr       tickFlag          ; Clear tick flag 
          clr       nsReq             ; No NS walk request 
          clr       ewReq             ; No EW walk request 

          sei                         ; Enable global interrupts 

; application main loop 
; ------------------------------------------------------------ 
main_loop: 
          tst       tickFlag            ; Check if a 100ms tick occurred 
          breq      main_loop           ; If zero, keep waiting here 

          clr       tickFlag            ; Clear tickFlag for next tick 
          
          ; increment state timer 
          lds       r16, stateTimer     ; Load current state time 
          inc       r16                 ; +1 tick (100ms) 
          sts       stateTimer, r16     ; Store back 
          
          call      check_state         ; Run FSM logic for this tick 
          rjmp      main_loop           ; Loop forever 

; state machine logic 
; ------------------------------------------------------------ 
check_state: 
          lds       r17, state          ; Load current FSM state into r17 

          ; check which state we are in 
          cpi       r17, 0              ; Check State 0
          brne      check_st_1          ; If not 0, check next
          rjmp      do_ns_green         ; If 0, jump to handler

check_st_1:
          cpi       r17, 1              ; Check State 1
          brne      check_st_2
          rjmp      do_ns_yellow      

check_st_2:
          cpi       r17, 2              ; Check State 2
          brne      check_st_3
          rjmp      do_all_red_1      

check_st_3:
          cpi       r17, 3              ; Check State 3
          brne      check_st_4
          rjmp      do_ew_green       

check_st_4:
          cpi       r17, 4              ; Check State 4
          brne      check_st_5
          rjmp      do_ew_yellow      

check_st_5:
          cpi       r17, 5              ; Check State 5
          brne      end_check_state
          rjmp      do_all_red_2      

end_check_state:
          ret                           ; If state out of range, just return 

; State 0: NS Green 
; ------------------------------------------------------------ 
do_ns_green: 
          ; set lights 
          sbi       PORTB, NS_GRN       ; Turn NS green ON 
          cbi       PORTB, NS_YEL       ; Turn NS yellow OFF 
          cbi       PORTB, NS_RED       ; Turn NS red OFF 
          sbi       PORTC, EW_RED       ; Turn EW red ON (EW stops) 
          call      safe_ped_lights     ; Both sides: don't-walk on, walk off 

          ; check time (20 ticks = 2s) 
          lds       r16, stateTimer     ; Load how long we've been in this state 
          cpi       r16, 20             ; Has it been 2 seconds? 
          brsh      chg_st_0            ; If greater or equal, change state
          ret                           ; Otherwise, keep waiting

chg_st_0:
          ; switch to next state
          ldi       r16, 1              ; Load next state ID (1)
          sts       state, r16          ; Save new state 
          clr       r16                 ; Clear the timer
          sts       stateTimer, r16     ; Reset timer for next state
          ret

; State 1: NS Yellow 
; ------------------------------------------------------------ 
do_ns_yellow: 
          cbi       PORTB, NS_GRN       ; Turn OFF Green
          sbi       PORTB, NS_YEL       ; Turn ON Yellow
          call      safe_ped_lights     ; Ensure pedestrians wait

          lds       r16, stateTimer     ; Get current time
          cpi       r16, 20             ; Wait 2 second (20 ticks)
          brsh      chg_st_1            ; If done, switch state
          ret                           ; Else return

chg_st_1:
          ldi       r16, 2              ; Next state ID (2)
          sts       state, r16          ; Save new state 
          clr       r16                 ; r16 = 0 
          sts       stateTimer, r16     ; Reset state timer 
          ret

; State 2: All Red (Check NS Walk) 
; ------------------------------------------------------------ 
do_all_red_1: 
          cbi       PORTB, NS_YEL       ; Turn OFF Yellow
          sbi       PORTB, NS_RED       ; Turn ON Red
          sbi       PORTC, EW_RED       ; Keep EW Red ON (Safety delay)
          
          ; see if someone pushed the button
          tst       nsReq               ; Check the NS request flag
          breq      skip_ns_walk        ; If 0, skip the walk logic
          
          ; handle the crosswalk
          call      handle_ns_walk      ; Run the walk light sequence
          ret                           ; Stay in this state while walking

skip_ns_walk: 
          call      safe_ped_lights     ; Ensure walk lights are OFF
          lds       r16, stateTimer     ; Get current time
          cpi       r16, 20             ; Wait 2 seconds for safety
          brsh      chg_st_2            ; If done, switch state
          ret

chg_st_2:
          ldi       r16, 3              ; Next state ID (3)
          sts       state, r16          ; Save it
          clr       r16 
          sts       stateTimer, r16     ; Reset timer
          ret

; State 3: EW Green 
; ------------------------------------------------------------ 
do_ew_green: 
          sbi       PORTB, NS_RED       ; Keep NS Red ON
          sbi       PORTC, EW_GRN       ; Turn ON East-West Green
          cbi       PORTC, EW_RED       ; Turn OFF East-West Red
          call      safe_ped_lights     ; Ensure pedestrians wait

          lds       r16, stateTimer     ; Get current time
          cpi       r16, 20             ; Wait 2 seconds (20 ticks)
          brsh      chg_st_3            ; If done, switch state
          ret

chg_st_3:
          ldi       r16, 4              ; Next state ID (4)
          sts       state, r16          ; Save it
          clr       r16 
          sts       stateTimer, r16     ; Reset timer
          ret

; State 4: EW Yellow 
; ------------------------------------------------------------ 
do_ew_yellow: 
          cbi       PORTC, EW_GRN       ; Turn OFF Green
          sbi       PORTC, EW_YEL       ; Turn ON Yellow
          call      safe_ped_lights     ; Ensure pedestrians wait

          lds       r16, stateTimer     ; Get current time
          cpi       r16, 20             ; Wait 2 seconds (20 ticks)
          brsh      chg_st_4            ; If done, switch state
          ret

chg_st_4:
          ldi       r16, 5              ; Next state ID (5)
          sts       state, r16          ; Save it
          clr       r16 
          sts       stateTimer, r16     ; Reset timer
          ret

; State 5: All Red (Check EW Walk) 
; ------------------------------------------------------------ 
do_all_red_2: 
          cbi       PORTC, EW_YEL       ; Turn OFF Yellow
          sbi       PORTC, EW_RED       ; Turn ON Red
          sbi       PORTB, NS_RED       ; Keep NS Red ON
          
          tst       ewReq               ; Check if EW button was pressed
          breq      skip_ew_walk        ; If not, skip walk logic

          call      handle_ew_walk      ; Run walk light sequence
          ret                           ; Stay here while walking

skip_ew_walk: 
          call      safe_ped_lights     ; Ensure walk lights are OFF
          lds       r16, stateTimer     ; Get current time
          cpi       r16, 20             ; Wait 2 seconds for safety
          brsh      chg_st_5            ; If done, switch state
          ret

chg_st_5:
          ldi       r16, 0              ; Loop back to Start (State 0)
          sts       state, r16          ; Save it
          clr       r16 
          sts       stateTimer, r16     ; Reset timer
          ret

; Subroutines 
; ------------------------------------------------------------ 
safe_ped_lights: 
          cbi       PORTB, NS_WLK       ; Turn OFF NS Walk Light
          sbi       PORTB, NS_DWK       ; Turn ON NS Don't Walk Light

          cbi       PORTC, EW_WLK       ; Turn OFF EW Walk Light
          sbi       PORTC, EW_DWK       ; Turn ON EW Don't Walk Light
          ret                           ; Go back

handle_ns_walk: 
          lds       r18, walkTimer      ; Get the walk timer value
          inc       r18                 ; Add 1 to it
          sts       walkTimer, r18      ; Save it
          
          ; pause the main timer so we don't leave this state yet
          clr       r16 
          sts       stateTimer, r16     ; Keep state timer at 0

          cbi       PORTB, NS_DWK       ; Turn OFF the Don't Walk light
          
          ; logic to blink the light
          cpi       r18, 20             ; Is it the first 2 seconds?
          brlo      ns_solid_on         ; If yes, keep light solid

          sbrc      r18, 2              ; Check a specific bit to toggle (blink)
          rjmp      ns_blink_off        ; If bit is 1, turn off

ns_solid_on: 
          sbi       PORTB, NS_WLK       ; Turn ON Walk light
          rjmp      check_ns_done       ; Skip the off command

ns_blink_off: 
          cbi       PORTB, NS_WLK       ; Turn OFF Walk light

check_ns_done: 
          cpi       r18, 40             ; Have 4 seconds passed?
          brlo      end_ns_walk_handle  ; If not, keep going

          clr       nsReq               ; Clear the button request flag
          clr       r18                 ; Reset the walk timer
          sts       walkTimer, r18 
end_ns_walk_handle: 
          ret                           ; Go back

handle_ew_walk: 
          lds       r18, walkTimer      ; Get walk timer
          inc       r18                 ; Increment it
          sts       walkTimer, r18      ; Save it
          
          clr       r16 
          sts       stateTimer, r16     ; Pause main timer

          cbi       PORTC, EW_DWK       ; Turn OFF Don't Walk
          
          cpi       r18, 20             ; First 2 seconds?
          brlo      ew_solid_on         ; Keep solid

          sbrc      r18, 2              ; Check bit for blinking
          rjmp      ew_blink_off        ; Turn off if bit is set

ew_solid_on: 
          sbi       PORTC, EW_WLK       ; Turn ON Walk
          rjmp      check_ew_done     

ew_blink_off: 
          cbi       PORTC, EW_WLK       ; Turn OFF Walk

check_ew_done: 
          cpi       r18, 40             ; 4 seconds passed?
          brlo      end_ew_walk_handle 

          clr       ewReq               ; Clear request flag
          clr       r18                 ; Reset timer
          sts       walkTimer, r18 
end_ew_walk_handle: 
          ret                         

; ISRs 
; ------------------------------------------------------------ 
ns_btn_isr: 
          ldi       nsReq, 1            ; Remember that NS button was pressed
          reti                          ; Return from interrupt

ew_btn_isr: 
          ldi       ewReq, 1            ; Remember that EW button was pressed
          reti                          ; Return from interrupt

timer_isr: 
          ldi       tickFlag, 1         ; Signal that 100ms has passed
          reti                          ; Return from interrupt


