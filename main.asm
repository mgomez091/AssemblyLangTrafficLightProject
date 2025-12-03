;
; trafficLightProject.asm
;
; Created: 11/29/2025 6:06:02 PM
; Author : Miguel Getzain Gomez, Richard Ortega, Cheleyson Dorvilien
; Desc   : Using 

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

; East-West Lights
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
.def nsReq = r22                        ; N/S 
.def ewReq = r23                        ; Flag: EW crosswalk request 

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
          tst       tickFlag          ; Check if a 100ms tick occurred 
          breq      main_loop         ; If zero, keep waiting here 

          clr       tickFlag          ; Clear tickFlag for next tick 
          
          ; Increment State Timer 
          lds       r16, stateTimer   ; Load current state time 
          inc       r16               ; +1 tick (100ms) 
          sts       stateTimer, r16   ; Store back 
          
          call      check_state       ; Run FSM logic for this tick 
          rjmp      main_loop         ; Loop forever 

; state machine logic 
; ------------------------------------------------------------ 
check_state: 
          lds       r17, state        ; Load current FSM state into r17 

          ; Check which state we are in 
          ; Uses brne + rjmp to solve "branch out of reach" errors
          
          cpi       r17, 0            ; Check State 0
          brne      check_st_1        ; If not 0, check next
          rjmp      do_ns_green       ; If 0, jump to handler

check_st_1:
          cpi       r17, 1            ; Check State 1
          brne      check_st_2
          rjmp      do_ns_yellow      

check_st_2:
          cpi       r17, 2            ; Check State 2
          brne      check_st_3
          rjmp      do_all_red_1      

check_st_3:
          cpi       r17, 3            ; Check State 3
          brne      check_st_4
          rjmp      do_ew_green       

check_st_4:
          cpi       r17, 4            ; Check State 4
          brne      check_st_5
          rjmp      do_ew_yellow      

check_st_5:
          cpi       r17, 5            ; Check State 5
          brne      end_check_state
          rjmp      do_all_red_2      

end_check_state:
          ret                         ; If state out of range, just return 

; State 0: NS Green 
; ------------------------------------------------------------ 
do_ns_green: 
          ; Set Lights 
          sbi       PORTB, NS_GRN     ; Turn NS green ON 
          cbi       PORTB, NS_YEL     ; Turn NS yellow OFF 
          cbi       PORTB, NS_RED     ; Turn NS red OFF 
          sbi       PORTC, EW_RED     ; Turn EW red ON (EW stops) 
          call      safe_ped_lights   ; Both sides: don't-walk on, walk off 

          ; Check Time (20 ticks = 2s) 
          lds       r16, stateTimer   ; Load how long we've been in this state 
          cpi       r16, 20           ; Has it been 2 seconds? 
          brsh      chg_st_0          ; If >= 20, change state
          ret                         ; Else, return to main loop

chg_st_0:
          ; Change State 
          ldi       r16, 1            ; Next state = 1 (NS yellow) 
          sts       state, r16        ; Save new state 
          clr       r16               ; r16 = 0 
          sts       stateTimer, r16   ; Reset state timer 
          ret

; State 1: NS Yellow 
; ------------------------------------------------------------ 
do_ns_yellow: 
          cbi       PORTB, NS_GRN     ; Turn NS green OFF 
          sbi       PORTB, NS_YEL     ; Turn NS yellow ON 
          call      safe_ped_lights   ; Pedestrians: don't-walk 

          lds       r16, stateTimer   ; Load state timer 
          cpi       r16, 10           ; Wait 1 seconds in yellow 
          brsh      chg_st_1          ; If >= 10, change state
          ret                         ; Else return

chg_st_1:
          ldi       r16, 2            ; Next state = 2 (all-red, NS walk check) 
          sts       state, r16        ; Save new state 
          clr       r16               ; r16 = 0 
          sts       stateTimer, r16   ; Reset state timer 
          ret

; State 2: All Red (Check NS Walk) 
; ------------------------------------------------------------ 
do_all_red_1: 
          cbi       PORTB, NS_YEL     ; Ensure NS yellow is OFF 
          sbi       PORTB, NS_RED     ; NS red ON 
          sbi       PORTC, EW_RED     ; EW red ON (both directions red) 
          
          ; Check NS Walk Request 
          tst       nsReq             ; Is there a NS walk request? 
          breq      skip_ns_walk      ; If zero, skip special walk handling 
          
          ; Handle Walk Logic 
          call      handle_ns_walk    ; Manage NS walk/blink timing 
          ret                         ; Don't advance state while walking 

skip_ns_walk: 
          call      safe_ped_lights   ; No walk requested: both don't-walk 
          lds       r16, stateTimer   ; Load time in all-red state 
          cpi       r16, 10           ; Stay here 1 seconds as safety delay 
          brsh      chg_st_2          ; If >= 10, change state
          ret                         ; Else return

chg_st_2:
          ldi       r16, 3            ; Next state = 3 (EW green) 
          sts       state, r16        ; Update state 
          clr       r16 
          sts       stateTimer, r16   ; Reset state timer 
          ret

; State 3: EW Green 
; ------------------------------------------------------------ 
do_ew_green: 
          sbi       PORTB, NS_RED     ; NS red ON 
          sbi       PORTC, EW_GRN     ; EW green ON 
          cbi       PORTC, EW_RED     ; EW red OFF 
          call      safe_ped_lights   ; Pedestrians: don't-walk 

          lds       r16, stateTimer   ; Load time in EW green 
          cpi       r16, 20           ; 2 seconds of EW green 
          brsh      chg_st_3          ; If >= 20, change state
          ret                         ; Else return

chg_st_3:
          ldi       r16, 4            ; Next state = 4 (EW yellow) 
          sts       state, r16        ; Update state 
          clr       r16 
          sts       stateTimer, r16   ; Reset state timer 
          ret

; State 4: EW Yellow 
; ------------------------------------------------------------ 
do_ew_yellow: 
          cbi       PORTC, EW_GRN     ; Turn EW green OFF 
          sbi       PORTC, EW_YEL     ; Turn EW yellow ON 
          call      safe_ped_lights   ; Pedestrians: don't-walk 

          lds       r16, stateTimer   ; Load timer 
          cpi       r16, 10           ; Wait 1 seconds in yellow 
          brsh      chg_st_4          ; If >= 10, change state
          ret

chg_st_4:
          ldi       r16, 5            ; Next state = 5 (all-red, EW walk check) 
          sts       state, r16        ; Update state 
          clr       r16 
          sts       stateTimer, r16   ; Reset state timer 
          ret

; State 5: All Red (Check EW Walk) 
; ------------------------------------------------------------ 
do_all_red_2: 
          cbi       PORTC, EW_YEL     ; Make sure EW yellow is OFF 
          sbi       PORTC, EW_RED     ; EW red ON 
          sbi       PORTB, NS_RED     ; NS red ON (both red again) 
          
          tst       ewReq             ; Is there an EW walk request? 
          breq      skip_ew_walk      ; If not, skip walk handling 

          call      handle_ew_walk    ; Handle EW walk/blink 
          ret                         ; Stay here while walk active 

skip_ew_walk: 
          call      safe_ped_lights   ; No walk: both don't-walk ON 
          lds       r16, stateTimer   ; Load time in this all-red 
          cpi       r16, 10           ; Wait 1 seconds 
          brsh      chg_st_5          ; If >= 10, change state
          ret

chg_st_5:
          ldi       r16, 0            ; Go back to state 0 (NS green) 
          sts       state, r16        ; Save state 
          clr       r16 
          sts       stateTimer, r16   ; Reset timer 
          ret

; Subroutines 
; ------------------------------------------------------------ 
safe_ped_lights: 
          cbi       PORTB, NS_WLK     ; Turn NS walk OFF 
          sbi       PORTB, NS_DWK     ; Turn NS don't-walk ON 

          cbi       PORTC, EW_WLK     ; Turn EW walk OFF 
          sbi       PORTC, EW_DWK     ; Turn EW don't-walk ON 
          ret                         ; Return to caller 

handle_ns_walk: 
          lds       r18, walkTimer    ; Load walk timer 
          inc       r18               ; Advance walk timer by 1 tick 
          sts       walkTimer, r18    ; Store back 
          
          ; Pause State Timer so red phase doesn't auto-advance 
          clr       r16 
          sts       stateTimer, r16   ; Freeze stateTimer while walking 

          cbi       PORTB, NS_DWK     ; Turn NS don't-walk OFF (allow walking) 
          
          ; Blink Logic: solid first half, blink second half 
          cpi       r18, 20           ; First 2s = solid ON 
          brlo      ns_solid_on       ; If <20, solid walk 

          sbrc      r18, 2            ; Test bit 2 of walkTimer to blink 
          rjmp      ns_blink_off      ; If bit set, turn walk OFF 

ns_solid_on: 
          sbi       PORTB, NS_WLK     ; Turn NS walk ON 
          rjmp      check_ns_done     ; Skip OFF code 

ns_blink_off: 
          cbi       PORTB, NS_WLK     ; Turn NS walk OFF 

check_ns_done: 
          cpi       r18, 40           ; Total of 40 ticks (4 seconds) 
          brlo      end_ns_walk_handle ; If less, keep walking 

          clr       nsReq             ; Done: clear NS request flag 
          clr       r18               ; Reset walk timer 
          sts       walkTimer, r18 
end_ns_walk_handle: 
          ret                         ; Return to caller 

handle_ew_walk: 
          lds       r18, walkTimer    ; Load walk timer 
          inc       r18               ; Advance walk timer 
          sts       walkTimer, r18    ; Store back 
          
          clr       r16 
          sts       stateTimer, r16   ; Pause state timer during walk 

          cbi       PORTC, EW_DWK     ; Turn EW don't-walk OFF 
          
          cpi       r18, 20           ; First 2s solid ON 
          brlo      ew_solid_on       ; If <20, solid 

          sbrc      r18, 2            ; Use bit 2 for blinking 
          rjmp      ew_blink_off      ; If bit set, turn OFF 

ew_solid_on: 
          sbi       PORTC, EW_WLK     ; Turn EW walk ON 
          rjmp      check_ew_done     ; Skip OFF code 

ew_blink_off: 
          cbi       PORTC, EW_WLK     ; Turn EW walk OFF 

check_ew_done: 
          cpi       r18, 40           ; 4 seconds total walk time 
          brlo      end_ew_walk_handle ; If less, continue walking 

          clr       ewReq             ; Clear EW walk request 
          clr       r18               ; Reset walk timer 
          sts       walkTimer, r18 
end_ew_walk_handle: 
          ret                         ; Return to caller 

; ISRs 
; ------------------------------------------------------------ 
ns_btn_isr: 
          ldi       nsReq, 1          ; Set NS walk request flag 
          reti                        ; Return from interrupt 

ew_btn_isr: 
          ldi       ewReq, 1          ; Set EW walk request flag 
          reti                        ; Return from interrupt 

timer_isr: 
          ldi       tickFlag, 1       ; Set tick flag (100ms elapsed) 
          reti                        ; Return from interrupt
