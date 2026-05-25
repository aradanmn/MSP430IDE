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

    static func create(at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try mainC.write(to: url.appendingPathComponent("main.c"), atomically: true, encoding: .utf8)
        try tomlContent.write(to: url.appendingPathComponent("msp430.toml"), atomically: true, encoding: .utf8)
        try gitignore.write(to: url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    }
}
