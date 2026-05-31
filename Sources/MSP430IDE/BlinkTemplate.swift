import Foundation

enum BlinkTemplate {
    static let mainC = """
    #include <msp430.h>

    int main(void) {
        WDTCTL = WDTPW | WDTHOLD;

        P1DIR |= BIT0;
        P1OUT &= ~BIT0;

        for (;;) {
            P1OUT ^= BIT0;
            __delay_cycles(200000);
        }
    }
    """

    static let tomlContent = """
    [project]
    mcu  = "msp430g2553"
    mode = "native"

    [flash]
    driver = "tilib"
    env    = { DYLD_LIBRARY_PATH = "~/.local/lib" }

    [defaults]
    cflags = ["-Wall", "-Wextra", "-g"]

    # Debug and Release configs are auto-injected.
    # Override or add custom configs here, e.g.:
    # [configs.Production]
    # cflags  = ["-Os", "-flto"]
    # defines = ["PRODUCTION=1"]
    """

    static let gitignore = """
    build/
    .msp430ide/
    .DS_Store
    """

    /// clangd config that suppresses false positives from GCC MSP430 built-ins
    /// (e.g. __delay_cycles) that clang's frontend doesn't know about.
    static let clangdConfig = """
    CompileFlags:
      Add:
        # __delay_cycles and other MSP430 GCC built-ins are unknown to clangd.
        - -Wno-implicit-function-declaration
    """

    static func create(at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try mainC.write(to: url.appendingPathComponent("main.c"), atomically: true, encoding: .utf8)
        try tomlContent.write(to: url.appendingPathComponent("msp430.toml"), atomically: true, encoding: .utf8)
        try gitignore.write(to: url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try clangdConfig.write(to: url.appendingPathComponent(".clangd"), atomically: true, encoding: .utf8)
    }

    // MARK: - Assembly template

    static let mainS = """
    ; Bare-metal blink for the MSP430G2553 LaunchPad — red LED on P1.0.
    ; Assembled with the C preprocessor, so <msp430.h> register names work.
    #include <msp430.h>

            .text
            .global _start
    _start:
            mov.w   #(WDTPW|WDTHOLD), &WDTCTL   ; stop the watchdog
            mov.w   #0x0400, SP                 ; init stack pointer (top of RAM)
            bis.b   #BIT0, &P1DIR              ; P1.0 as output

    loop:
            xor.b   #BIT0, &P1OUT             ; toggle the LED
            mov.w   #0x000F, R12              ; ~1 Hz software delay
    outer:
            mov.w   #0xFFFF, R13
    inner:
            dec.w   R13
            jnz     inner
            dec.w   R12
            jnz     outer
            jmp     loop

            ; Reset vector: 0xFFFE = .vectors (forced to 0xFFE0) + offset 0x1E.
            .section .vectors, "a"
            .org 0x1E
            .word _start
    """

    static let asmToml = """
    [project]
    mcu  = "msp430g2553"
    mode = "native"

    [flash]
    driver = "tilib"
    env    = { DYLD_LIBRARY_PATH = "~/.local/lib" }

    # Assembly sources are compiled with these flags. The defaults below are
    # also what the IDE uses if you omit them:
    [defaults]
    asmflags = ["-x", "assembler-with-cpp", "-nostdlib"]
    """

    static func createAssembly(at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try mainS.write(to: url.appendingPathComponent("main.s"), atomically: true, encoding: .utf8)
        try asmToml.write(to: url.appendingPathComponent("msp430.toml"), atomically: true, encoding: .utf8)
        try gitignore.write(to: url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    }
}
