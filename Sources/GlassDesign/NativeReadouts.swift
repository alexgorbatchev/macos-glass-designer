import Foundation

/// Native values of AppKit's private glass objects. Overrides overwrite an object's own inputs,
/// so each object's values are captured before the designer first writes to it.
@MainActor
final class NativeReadouts {
  private final class Record {
    var natives: [String: Double] = [:]
    var written: [String: Double] = [:]
  }

  /// Weak keys: AppKit replaces these objects whenever it rebuilds the material.
  private let records = NSMapTable<NSObject, Record>.weakToStrongObjects()

  /// Current native values of `object`. A live value other than the designer's last write means
  /// AppKit rebuilt or retuned the material, so it becomes the new native value.
  func natives(of object: NSObject, keys: [String], read: (String) -> Double?) -> [String: Double] {
    let record = record(for: object)
    for key in keys {
      let live = read(key)
      // Core Animation may store inputs at single precision.
      if let live, let written = record.written[key], Float(live) == Float(written) { continue }
      record.natives[key] = live
    }
    return record.natives
  }

  func recordWrites(_ values: [String: Double], to object: NSObject) {
    record(for: object).written = values
  }

  private func record(for object: NSObject) -> Record {
    if let record = records.object(forKey: object) { return record }
    let record = Record()
    records.setObject(record, forKey: object)
    return record
  }
}
