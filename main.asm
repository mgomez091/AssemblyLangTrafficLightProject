;
; trafficLightProject.asm
;
; Created: 11/29/2025 6:06:02 PM
; Author : mgome
;

; Declare constants and global variables
;------------------------------------------------------------------------------
              ;  us   * XTAL / scaler - 1 
.equ DELAY_MS = 100000 * (16 / 256.00) - 1

.equ RED_LIGHT_PIN = PB2
.equ YLW_LIGHT_PIN = PD2
.equ GRN_LIGHT_PIN = PC2


; Vector Table
;------------------------------------------------------------------------------
.org 0x000                                        ; reset
          jmp       main
.org INT0addr                                     ; External Interrupt request 0 (Port-B Pin-2)
          jmp       btn_dec_isr
.org INT1addr                                     ; External Interrupt request 1 (Port-C Pin-3)
          jmp       btn_inc_isr
.org OC1Aaddr                                     ; Timer/Counter1 Compare Match A
          jmp       timer1_isr          
.org INT_VECTORS_SIZE                             ; End vector table




; show LED for n milliseconds
; @param ledCounter
; ------------------------------------------------------------
blink_led:
          sbi       PORTB, LED_PIN                ; turn LED on
          lds       r16,ledCounter                ; r16 = ledCounter
delay_lp:                                         ; do {
          call      delay
          dec       r16                           ; --r16
          brne      delay_lp                      ; } while (r16 > 0);
          cbi       PORTB, LED_PIN                ; turn LED off
          ret                                     ; blink_led

;----------------------------------------------------------------------------------------------------------
delay:
          ; Load TCNT1H:TCNT1L with initial count
          clr       r20
          sts       TCNT1H, r20
          sts       TCNT1L, r20

          ; Load OCR1AH:OCR1AL with stop count
          ldi       r20, high(DELAY_MS)
          sts       OCR1AH, r20
          ldi       r20, low(DELAY_MS)
          sts       OCR1AL, r20
          
          ; Load TCCR1A & TCCR1B
          clr       r20
          sts       TCCR1A, r20                   ; CTC mode
          ldi       r20, (1 << WGM12) | (1 << CS12)
          sts       TCCR1B, r20                   ; Clock Prescaler – setting the clock starts the timer

          ldi       r20, (1 << OCIE1A)
          sts       TIMSK1, r20

          ; Monitor OCF1A flag in TIFR1
Monitor_OCF1A:
          sbis      TIFR1, OCF1A
          rjmp      Monitor_OCF1A

          ; Stop timer by clearing clock (clear TCCR1B)
          clr       r20
          sts       TCCR1B, r20

          ; Clear OCF1A flag – write a 1 to OCF1A bit in TIFR1
          ldi       r20, (1 << OCF1A)
          out       TIFR1, r20

          ; Repeat steps again for multiple timers
          ret                 ;delay

; handle decrement button press
;----------------------------------------------------------------------------------
btn_dec_isr:
          ldi       decFlag, 1                    ; decFlag = true

          reti                                    ; btn_dec_isr

; handle increment button press
;----------------------------------------------------------------------------------
btn_inc_isr:
          ldi       incFlag, 1                    ; incFlag = true

          reti                                    ; btn_inc_isr

timer1_isr:
          ldi       tmFlag, 1                     ; 

          ; Load TCNT1H:TCNT1L with initial count
          clr       r20
          sts       TCNT1H, r20
          sts       TCNT1L, r20

          
          reti
