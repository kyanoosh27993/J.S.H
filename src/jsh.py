"""J.S.H — نقطه‌ی شروع برنامه."""

import sys

APP_NAME = "J.S.H"
APP_VERSION = "0.1.0"


def main() -> int:
    print(f"{APP_NAME} نسخه {APP_VERSION}")
    print("برنامه راه‌اندازی شد. مشخصات نهایی برنامه در docs/SPEC.md ثبت خواهد شد.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
