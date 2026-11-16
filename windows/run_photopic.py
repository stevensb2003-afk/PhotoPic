"""PyInstaller entrypoint preserving package imports for photopic_win."""

from photopic_win.main import main

if __name__ == "__main__":
    raise SystemExit(main())
