[bits   32]
[org    0x9000]

jmp _entry
; ProtectMode Entry Point Jump
nop

KernelMode db 32
; 위의 값을 이용하여 커널 버전을 판단한다.

_entry:
    jmp _protect_entry
    ; 이 부분에 각종 라이브러리 함수 파일들이 include 된다.

    ; Kernel Library
    %include "kernel.library.print.asm"
    %include "kernel.library.debug.asm"
    %include "kernel.library.queue.asm"
    ; 화면 출력 함수
    %include "kernel.vbe.header.asm"
    ; Vedio BIOS Extension Library
    %include "kernel.gdt.asm"
    ; gdt table 관련 함수 정의
    %include "kernel.gdt.header.asm"
    ; gdt table 정의
    ;%include "kernel.file.asm"
    ; 파일경로를 인자로 하여 해당 파일의 내용을 리턴하는 함수
    %include "kernel.vesa.graphice.asm"
    ; 비디오 카드 표준에 관한 VESA 처리에 대한 라이브러리
    %include "kernel.a20.mode.asm"
    ; 32bit 에서 64KB 까지의 메모리만 접근 가능한 제한을 풀기 위한
    ; A20 기능 활성화 라이브러리
    %include "kernel.mmu.asm"
    ; 메모리 관련 함수(페이징 처리)
    %include "kernel.pic.asm"
    ; pic 관련 함수 라이브러리
    %include "kernel.interrupt.asm"
    ; 인터럽트 관련 처리 함수
    %include "kernel.interrupt.handler.asm"
    ; Call Vector Table
    %include "kernel.call.table.asm"
    ; Resource
    %include "./Resource/kernel.mouse.asm"
    %include "./Resource/kernel.font.asm"
    ; Device Driver Function Table
    %include "./Interrupt/kernel.keyboard.asm"
    %include "./Interrupt/kernel.mouse.asm"

_global_variables:
    ;------------------------------------------------------------------------------------
    ; 변수 처리
    InfoTrueMessage:            db 'True', 0
    InfoFalseMessage:           db 'False', 0
    ; TRUE/ FALSE
    KernelProtectModeMessage:   db 'Switching Kernel Protected Mode -- ', 0
    ; 커널 보호모드 진입 완료 메시지
    A20SwitchingCheckMessage:   db 'A20 Switching Check -------------- ', 0
    ; A20 스위칭 성공 여부에 따른 메시지
    EnoughMemoryCheckMessage:   db '64MiB Physical Memory Check ------ ', 0
    ; 최소 64MiB 이상의 물리메모리인가에 따른 메시지
    Paging32ModeMessage:        db '32bit None-PAE Paging Mode ------- ', 0
    ; 32bit 페이징 처리 완료 메시지
    ;------------------------------------------------------------------------------------
    VbeSupportVersionMessage:   db 'VBE Support Version -------------- ', 0
    ; 그래픽 모드 지원 버전 체크 메시지
    KeyboardActiveMessage:      db 'Keyboard Active Status ----------- ', 0
    MouseActiveMessage:         db 'Mouse Active Status -------------- ', 0
    ; 각종 디바이스 초기화 상태 메시지
;----------------------------------------------
; 보호모드 진입
;----------------------------------------------
_protect_entry:
    mov ax, DataDescriptor
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    call _init_pic
    ; pic 초기화 수행

    ;-------------------------------------------------------------
    ; GDT, TSS 초기화
    ;-------------------------------------------------------------
    call _kernel_init_gdt_table
    ; GDT 새로운 메모리 주소에 등록

    call _kernel_load_gdt
    ; GDT 로드

    ; GUI 모드 함수 등록
    test byte [VbeGraphicModeStart], 0x01
    jz .jmp_gui_func

    mov dword [_cvt.clear], _vga_clear_screen
    mov dword [_cvt.print], _call_print32_gui
    ; function setting

.jmp_gui_func:
    mov ebx, 0xFFFFFF
    call _call_clear
    ; 화면 지우기

    ; 32bit Protected Mode 시작 엔트리 포인트 지점
    push 0
    push 0
    push 0x07
    push KernelProtectModeMessage
    call _call_print
    ; 보호모드 전환 메시지

    mov esi, 0
    mov edi, .chk_pm_true
    jmp .info_true
.chk_pm_true:
    ; 보호모드 전환 성공

    ;-------------------------------------------------------------
    ; A20 활성화 및 메모리 체크
    ;-------------------------------------------------------------
    call _set_a20_mode
    ; A20 기능을 활성화 한다.

    call _test_a20_mode
    ; 이 부분에서 A20 기능의 활성화 여부를 테스트

    push 1
    push 0
    push 0x07
    push A20SwitchingCheckMessage
    call _call_print
    ; A20 스위칭 처리 메시지

    mov esi, 1
    mov edi, .chk_a20_true
    ; A20 전환 실패인 경우 이므로
    ; 시스템을 종료 시킨다.

    test ax, ax
    jz .info_false
    jmp .info_true
.chk_a20_true:
    ; A20 기능이 활성화 되어있음

    call _kernel_is_enough_memory
    ; OS 실행에 필요한 최소한의 64MB 메모리가 존재하는지 체크

    push 2
    push 0
    push 0x07
    push EnoughMemoryCheckMessage
    call _call_print

    mov esi, 2
    cmp ax, 0
    je .info_false
    ; 메모리 부족으로 인한 실패인 경우 이므로
    ; 시스템을 종료 시킨다.

    mov edi, .chk_mem_true
    jmp .info_true
.chk_mem_true:
    ; 64MiB 이상의 메모리가 확보되어 있음

    ;-------------------------------------------------------------
    ; 페이징 및 인터럽트 초기화
    ;-------------------------------------------------------------
    call _kernel_init_idt_table
    ; 인터럽트 테이블을 초기화 처리 해 준다.

    mov esi, dword [idtr]
    call _kernel_load_idt
    ; 인터럽트 디스크립터 테이블 등록

    call _kernel_init_paging
    ; 페이징 초기화, 활성화
    ; 실행된 순간 모든 주소는 논리주소로 해석됨...

    push 3
    push 0
    push 0x07
    push Paging32ModeMessage
    call _call_print
    ; 페이징 관련 메시지

    mov esi, 3
    mov edi, .chk_paging_true
    jmp .info_true
.chk_paging_true:
    ; 페이징 기능 활성화 완료

    push 4
    push 0
    push 0x07
    push VbeSupportVersionMessage
    call _call_print

    mov ax, word [VbeVersion]
    and ax, 0x0200
    xor ax, 0x0200
    mov dx, VbeInfoLoadError
    xor dx, word [VbeInfoState]
    add ax, dx
    ; vbe 2.0, 3.0인 경우
    ; vbe를 지원하는지를 체크한다.

    test ax, ax
    jnz .info_false
    ; vbe 상태 정보값 읽기 실패인 경우
    ; 커널 종료

    push 4
    push 36
    push 2
    push VbeVersion
    call _print_byte_dump32
    ; vbe를 2.0 이상 지원하는 경우
    ; 지원하는 vbe 버전을 출력
    ;
    ; 그래픽 모드 지원 버전 출력

    mov ax, 0
    call _mask_pic
    ; 모든 PIC 활성화

    sti
    ; 인터럽트 활성화

    mov di, TSSDescriptor
    call _kernel_load_tss
    ; TSS 설정

;    mov ebx, 0xFFFFFF
;    call _call_clear

    ; 각종 디바이스 활성화
    ;--------------------------------------------------------
    ; 키보드 디바이스 활성화
    ;--------------------------------------------------------
    push 5
    push 0
    push 0x07
    push KeyboardActiveMessage
    call _call_print

    push dword [KeyboardDataQueue]
    call _queue_init
    ; 시스템 키보드 큐 초기화

    call _IHTKeyboardInitialize
    ; 키보드 활성화

    mov esi, 5
    cmp eax, 0x01
    jne .info_false
    ; 활성화 실패!!

    mov edi, .kbd_act_true
    jmp .info_true
.kbd_act_true:
    ; 키보드 디바이스 활성화 완료
    ; Handler 등록
    mov edi, 33
    mov esi, _IHTKeyboardHandler
    call _kernel_set_interrupt_handler

    ;--------------------------------------------------------
    ; 마우스 디바이스 활성화
    ;--------------------------------------------------------
    push 6
    push 0
    push 0x07
    push MouseActiveMessage
    call _call_print

    push dword [MouseDataQueue]
    call _queue_init
    ; 시스템 마우스 큐 초기화

    call _IHTMouseInitialize
    ; 마우스 활성화

    mov esi, 6
    cmp eax, 0x01
    jne .info_false
    ; 활성화 실패!!

    mov edi, .mus_act_true
    jmp .info_true
.mus_act_true:
    ; 마우스 디바이스 활성화 완료
    ; Handler 등록
    mov edi, 44
    mov esi, _IHTMouseHandler
    call _kernel_set_interrupt_handler

;--------------------------------------------------------
; 커널 종료 및 성공 & 실패 메시지 출력
;--------------------------------------------------------
.end_kernel:
    hlt
    jmp .end_kernel

.info_false:
;    push esi
;    push 36
;    call _print32_gotoxy

    push esi
    push 36
    push 0xFF0004
    push InfoFalseMessage
    call _call_print
    jmp .end_kernel

.info_true:
;    push esi
;    push 36
;    call _print32_gotoxy

    push esi
    push 36
    push 0x66990A
    push InfoTrueMessage
    call _call_print
;
;    inc esi
;    push esi
;    push 0
;    call _print32_gotoxy
;    ; 다음줄로 포인터 이동
    jmp edi
