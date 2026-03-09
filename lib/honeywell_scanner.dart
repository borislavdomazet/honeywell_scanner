import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:honeywell_scanner/scanned_data.dart';
import 'package:honeywell_scanner/scanner_callback.dart';

export 'package:honeywell_scanner/code_format.dart';
export 'package:honeywell_scanner/scanned_data.dart';
export 'package:honeywell_scanner/scanner_callback.dart';

class HoneywellScanner {
  static const _METHOD_CHANNEL = "honeywellscanner";
  static const _IS_SUPPORTED = "isSupported";
  static const _IS_STARTED = "isStarted";
  static const _SET_PROPERTIES = "setProperties";
  static const _START_SCANNER = "startScanner";
  static const _RESUME_SCANNER = "resumeScanner";
  static const _PAUSE_SCANNER = "pauseScanner";
  static const _STOP_SCANNER = "stopScanner";
  static const _SOFTWARE_TRIGGER = "softwareTrigger";
  static const _START_SCANNING = "startScanning";
  static const _STOP_SCANNING = "stopScanning";
  static const _ON_DECODED = "onDecoded";
  static const _ON_ERROR = "onError";

  /// Plugin control flag (not a native Honeywell property).
  /// When true, plugin will avoid forcing its default scanner settings.
  static const String preserveHoneywellSettingsProperty =
      '__honeywell_scanner_preserve_existing_settings';

  static final List<HoneywellScanner> _instances = [];

  late MethodChannel _channel;
  ScannerCallback? _scannerCallback;
  OnScannerDecodeCallback? _onScannerDecodeCallback;
  OnScannerErrorCallback? _onScannerErrorCallback;

  HoneywellScanner({
    ScannerCallback? scannerCallback,
    OnScannerDecodeCallback? onScannerDecodeCallback,
    OnScannerErrorCallback? onScannerErrorCallback,
  }) {
    _channel = MethodChannel(_METHOD_CHANNEL);
    _scannerCallback = scannerCallback;
    _onScannerDecodeCallback = onScannerDecodeCallback;
    _onScannerErrorCallback = onScannerErrorCallback;
    _instances.add(this);
  }

  /// Sets the scanner callback as a class that implements the ScannerCallback
  /// interface
  void setScannerCallback(ScannerCallback scannerCallback) =>
      _scannerCallback = scannerCallback;

  /// Sets the scanner decode callback as a function that takes a ScannedData
  /// object as a parameter
  void setScannerDecodeCallback(OnScannerDecodeCallback value) =>
      _onScannerDecodeCallback = value;

  /// Sets the scanner error callback as a function that takes an Exception
  /// object as a parameter
  void setScannerErrorCallback(OnScannerErrorCallback value) =>
      _onScannerErrorCallback = value;

  Future<void> _onMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case _ON_DECODED:
          onDecoded(call.arguments);
          break;
        case _ON_ERROR:
          onError(Exception(call.arguments));
          break;
        default:
          print(call.arguments);
      }
    } catch (e) {
      print(e);
    }
  }

  ///Called when decoder has successfully decoded the code
  ///<br>
  ///Note that this method always called on a worker thread
  ///
  ///@param scannedData Encapsulates the result of decoding a barcode within an image
  void onDecoded(Map<dynamic, dynamic>? scannedDataMap) {
    if (scannedDataMap != null) {
      final scannedData = ScannedData.fromMap(scannedDataMap);
      _scannerCallback?.onDecoded(scannedData);
      _onScannerDecodeCallback?.call(scannedData);
    }
  }

  ///Called when error has occurred
  ///<br>
  ///Note that this method always called on a worker thread
  ///
  ///@param error Exception that has been thrown
  void onError(Exception error) {
    _scannerCallback?.onError(error);
    _onScannerErrorCallback?.call(error);
  }

  /// Check if device is supported. Take into account this plugin supports a list
  /// of Honeywell devices but not all, so this function ensures compatibility.
  Future<bool> isSupported() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>(_IS_SUPPORTED) ?? false;
  }

  /// Checks if the scanner is already started
  Future<bool> isStarted() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>(_IS_STARTED) ?? false;
  }

  /// Setting properties. By default **honeywell_scanner** sets properties to
  /// support all code formats from [CodeFormat] enum, it also sets the trigger
  /// control property to [autoControl] and disables browser launching when
  /// scanning urls.
  /// However you can set any property you want by using the
  /// [honeywellScanner.setProperties(properties)] in case you need some specific
  /// behavior from the scanner.
  /// Properties are represented as a [Map<String, dynamic>], so for instance if
  /// you want the scanner only scans 1D codes and you want the scanned [EAN-13]
  /// bar codes to include the last digit **(the check digit)** and want the scanned
  /// [Codabar] bar codes to include the **start/stop digits**; then you must
  /// set it on properties like:
  ///
  /// List&lt;CodeFormat&gt; codeFormats = CodeFormatUtils.ALL_1D_FORMATS;
  /// Map&lt;String, dynamic&gt; properties = {
  ///   ...CodeFormatUtils.getAsPropertiesComplement(codeFormats), //CodeFormatUtils.getAsPropertiesComplement(...) this function converts a list of CodeFormat enums to its corresponding properties representation.
  ///   'DEC_CODABAR_START_STOP_TRANSMIT': true, //This is the Codabar start/stop digit specific property
  ///   'DEC_EAN13_CHECK_DIGIT_TRANSMIT': true, //This is the EAN13 check digit specific property
  /// };
  /// honeywellScanner.setProperties(properties);
  ///
  Future<void> setProperties(Map<String, dynamic> mapProperties) {
    return _channel.invokeMethod(_SET_PROPERTIES, mapProperties);
  }

  /// Starts the scanner listener, at this point the app will be listening
  /// for any scanned code when you press the physical PDA button or
  /// your in-app button to scan codes
  Future<bool> startScanner() async {
    _channel.setMethodCallHandler(_onMethodCall);
    return await _channel.invokeMethod<bool>(_START_SCANNER) ?? false;
  }

  /// Use this function to resume the scanner from a paused or stopped state.
  Future<bool> resumeScanner() async {
    _channel.setMethodCallHandler(_onMethodCall);
    return await _channel.invokeMethod(_RESUME_SCANNER) ?? false;
  }

  /// Use this function to pause the scanner temporarily, for instance when your
  /// app goes o background. [pauseScanner] is different to [stopScanner] because
  /// it doesn't release the resources of the scanner.
  Future<bool> pauseScanner() async {
    return await _channel.invokeMethod(_PAUSE_SCANNER) ?? false;
  }

  /// Stops the scanner listener, this will release and close the scanner connection
  Future<bool> stopScanner() async {
    return await _channel.invokeMethod(_STOP_SCANNER) ?? false;
  }

  /// Activates or deactivates the scanner sensor to scan codes.
  Future<bool> softwareTrigger(bool state) async {
    return await _channel.invokeMethod(_SOFTWARE_TRIGGER, state) ?? false;
  }

  /// Activates the scanner sensor to scan codes. This is the same as pressing
  /// the PDA physical button. Calling this function would be the same as calling
  /// [softwareTrigger(true)]
  Future<bool> startScanning() async {
    return await _channel.invokeMethod(_START_SCANNING) ?? false;
  }

  /// Cancels the scanning. Calling this function would be the same as calling
  /// [softwareTrigger(false)]
  Future<bool> stopScanning() async {
    return await _channel.invokeMethod(_STOP_SCANNING) ?? false;
  }

  /// Dispose scanner, this function does multiple things:
  ///   1. Removes the scanning callback
  ///   2. Stops the scanner to release the connection
  ///   3. Resumes any previous scanner instance state
  /// Use this function when you are done with an instance of the scanner.
  Future<bool> disposeScanner() async {
    _channel.setMethodCallHandler(null);
    final result = await stopScanner();
    if (_instances.remove(this)) {
      if (_instances.isNotEmpty) {
        _instances.last.resumeScanner();
      }
    }
    return result;
  }
}
