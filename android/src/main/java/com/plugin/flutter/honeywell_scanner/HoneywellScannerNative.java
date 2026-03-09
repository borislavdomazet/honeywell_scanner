package com.plugin.flutter.honeywell_scanner;

import android.content.Context;
import com.honeywell.aidc.AidcManager;
import com.honeywell.aidc.BarcodeFailureEvent;
import com.honeywell.aidc.BarcodeReadEvent;
import com.honeywell.aidc.BarcodeReader;
import com.honeywell.aidc.InvalidScannerNameException;
import com.honeywell.aidc.UnsupportedPropertyException;
import java.util.HashMap;
import java.util.Map;

/**
 * Created by krrigan on 10/13/18.
 */

public class HoneywellScannerNative extends HoneywellScanner implements AidcManager.CreatedCallback,
        BarcodeReader.BarcodeListener {

    private boolean initialized, initializing, pendingResume, supported;
    private transient AidcManager scannerManager;
    private transient BarcodeReader scanner;
    private transient Map<String, Object> properties;

    private static final String PROPERTY_PRESERVE_EXISTING_SETTINGS =
            "__honeywell_scanner_preserve_existing_settings";
    private boolean preserveExistingSettings;

    public HoneywellScannerNative(Context context)
    {
        super(context);
        pendingResume = false;
        initialized = false;
        initializing = false;
        supported = false;
        preserveExistingSettings = false;
        init();
    }
    
    @Override
    public boolean isSupported() { return supported; }

    @Override
    public boolean isStarted() { return initialized && scanner != null; }

    private void init()
    {
        initializing = true;
        AidcManager.create(context, this);
    }

    @Override
    public void onCreated(AidcManager aidcManager)
    {
        try{
            supported = true;
            scannerManager = aidcManager;
            scanner = scannerManager.createBarcodeReader();
            // register bar code event listener
            scanner.addBarcodeListener(this);

            // Apply plugin defaults only when we do NOT preserve Honeywell Settings profile.
            if (!preserveExistingSettings) {
                try {
                    scanner.setProperty(BarcodeReader.PROPERTY_TRIGGER_CONTROL_MODE,
                            BarcodeReader.TRIGGER_CONTROL_MODE_AUTO_CONTROL);
                    scanner.setProperty(BarcodeReader.PROPERTY_DATA_PROCESSOR_LAUNCH_BROWSER, false);
                } catch (UnsupportedPropertyException e) {
                    onError(e);
                }
            }

            // register trigger state change listener
            // When using Automatic Trigger control do not need to implement the onTriggerEvent
            // function scanner.addTriggerListener(this);

            if (properties != null && !properties.isEmpty()) {
                scanner.setProperties(properties);
            }

            initialized = true;
            initializing = false;
            if (pendingResume) resumeScanner();
        }
        catch (InvalidScannerNameException e){
            onError(e);
        }
    }

    @Override
    public void onBarcodeEvent(BarcodeReadEvent barcodeReadEvent)
    {
        if(barcodeReadEvent != null) onDecoded(ScannedData.from(barcodeReadEvent));
    }

    @Override
    public void onFailureEvent(BarcodeFailureEvent barcodeFailureEvent)
    {
        //Do nothing with unrecognized code due to an incomplete scanning
//        if(barcodeFailureEvent != null) onError(new Exception(barcodeFailureEvent.toString()));
    }

    private void initProperties(){
        properties = new HashMap<>();
        properties.put(BarcodeReader.PROPERTY_AZTEC_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_CODABAR_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_CODE_39_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_CODE_93_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_CODE_128_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_DATAMATRIX_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_EAN_8_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_EAN_13_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_MAXICODE_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_PDF_417_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_QR_CODE_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_RSS_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_RSS_EXPANDED_ENABLED, true);
        properties.put(BarcodeReader.PROPERTY_UPC_A_ENABLE, true);
        properties.put(BarcodeReader.PROPERTY_UPC_E_ENABLED, true);
    }

    @Override
    public void setProperties(Map<String, Object> mapProperties)
    {
        if (mapProperties == null) return;

        Map<String, Object> incoming = new HashMap<>(mapProperties);

        Object preserve = incoming.remove(PROPERTY_PRESERVE_EXISTING_SETTINGS);
        if (preserve instanceof Boolean) {
            preserveExistingSettings = (Boolean) preserve;
        }

        if (preserveExistingSettings) {
            // Keep Honeywell Settings profile; apply only explicit overrides from Flutter.
            properties = new HashMap<>(incoming);
        } else {
            // Old behavior (backward compatible): force plugin defaults + overrides.
            initProperties();
            properties.putAll(incoming);
        }

        if (isStarted() && properties != null && !properties.isEmpty()) {
            scanner.setProperties(properties);
        }
    }

    /**
     * Sends a trigger up/down action
     * Parameters:
     * state - Whether to trigger the scanner on or off
     * Throws:
     * ScannerNotClaimedException
     * ScannerUnavailableException
     */
    @Override
    public void softwareTrigger(boolean state) throws Exception
    {
        if(isStarted())
            scanner.softwareTrigger(state);
        else
            throw new Exception("Scanner is stopped");
    }

    @Override
    public void startScanning() throws Exception
    {
        stopScanning();
        softwareTrigger(true);
    }

    @Override
    public void stopScanning() throws Exception
    {
        softwareTrigger(false);
    }

    @Override
    public boolean resumeScanner()
    {
        startScanner();
        return true;
    }

    @Override
    public boolean pauseScanner()
    {
        if (scanner != null) {
            // release the scanner claim so we don't get any scanner notifications while paused
            // and the scanner properties are restored to default.
            scanner.release();
        }
        pendingResume = false;
        return true;
    }

    @Override
    public boolean startScanner()
    {
        if (scanner != null){
            try {
                scanner.claim();
            } catch (Exception e) {
                onError(e);
                return false;
            }
        } else {
            pendingResume = true;
            if(!initialized && !initializing) init();
        }
        return true;
    }

    @Override
    public boolean stopScanner()
    {
        pendingResume = false;
        try
        {
            if (scanner != null) {
                // unregister barcode event listener
                scanner.removeBarcodeListener(this);

                // unregister trigger state change listener
                // When using Automatic Trigger control do not need to implement the onTriggerEvent
                // function scanner.removeTriggerListener(this);

                // release the scanner claim so we don't get any scanner notifications while paused
                // and the scanner properties are restored to default.
                scanner.release();

                // close BarcodeReader to clean up resources.
                scanner.close();
                scanner = null;
            }
        }
        catch(Exception e)
        {
            e.printStackTrace();
        }

        try
        {
            if (scannerManager != null) {
                // close AidcManager to disconnect from the scanner service.
                // once closed, the object can no longer be used.
                scannerManager.close();
                scannerManager = null;
            }
        }
        catch(Exception e)
        {
            e.printStackTrace();
        }
        initialized = false;
        return true;
    }
}