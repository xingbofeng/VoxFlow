// Logger.swift
// Adapted from DictusCore (commit 7264b1d8). MIT License — Copyright (c) 2026 PIVI Solutions.
// Logger type renamed from DictusLogger to AppLogger (brand-neutral).
// Subsystem changed from `com.pivi.dictus` to `com.mashangxie.ios`.
import os.log

/// Centralized loggers for Mashangxie subsystems.
/// Usage: AppLogger.keyboard.debug("message")
@available(iOS 14.0, macOS 11.0, *)
public enum AppLogger {
    public static let app = Logger(subsystem: "com.mashangxie.ios", category: "app")
    public static let keyboard = Logger(subsystem: "com.mashangxie.ios", category: "keyboard")
    public static let appGroup = Logger(subsystem: "com.mashangxie.ios", category: "appGroup")
}
