package io.gnucoop.facerec.plugin;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Rect;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;
import android.support.annotation.NonNull;
import android.support.media.ExifInterface;
import android.support.v4.content.FileProvider;
import android.util.Base64;
import android.util.Log;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.NativePlugin;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.PluginRequestCodes;
import com.getcapacitor.plugin.camera.ExifWrapper;
import com.getcapacitor.plugin.camera.ImageUtils;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.android.gms.tasks.Task;
import com.google.firebase.FirebaseApp;
import com.google.firebase.ml.vision.FirebaseVision;
import com.google.firebase.ml.vision.common.FirebaseVisionImage;
import com.google.firebase.ml.vision.face.FirebaseVisionFace;
import com.google.firebase.ml.vision.face.FirebaseVisionFaceDetector;
import com.google.firebase.ml.vision.face.FirebaseVisionFaceDetectorOptions;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.MalformedURLException;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;

import javax.net.ssl.HttpsURLConnection;

import org.tensorflow.lite.Interpreter;

@NativePlugin(
        permissions={
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
                Manifest.permission.CAMERA
        },
        requestCodes={FaceRec.REQUEST_INIT, FaceRec.REQUEST_IMAGE_CAPTURE, FaceRec.REQUEST_IMAGE_PICK}
)
public class FaceRec extends Plugin {
    static final int REQUEST_INIT = 9901;
    static final int REQUEST_IMAGE_CAPTURE = 9902;
    static final int REQUEST_IMAGE_PICK = 9903;
    static final String CACHE_PREFERENCES_NAME = "facerPluginCachePrefs";

    private static final int REQUEST_DOWNLOAD_MODELS = 10030;
    private static final String MISSING_INIT_PERMISSIONS = "Missing init permissions";
    private static final String INVALID_MODEL_URL_ERROR = "Invalid model URL";
    private static final String INVALID_PHOTO_SOURCE = "Invalid model URL";
    private static final String MODEL_DOWNLOAD_ERROR = "Unable to download model";
    private static final String NO_CAMERA_ERROR = "Device doesn't have a camera available";
    private static final String IMAGE_FILE_SAVE_ERROR = "Unable to create photo on disk";
    private static final String IMAGE_PROCESS_NO_FILE_ERROR = "Unable to process image, file not found on disk";
    private static final String UNABLE_TO_PROCESS_BITMAP = "Unable to process bitmap";
    private static final String UNABLE_TO_PROCESS_IMAGE = "Unable to process image";
    private static final String NO_IMAGE_PICKED = "No image picked";
    private static final String OUT_OF_MEMORY = "Out of memory";
    private static final String NO_IMAGE_FOUND = "No image found";

    private static final int COLOR_MALE = Color.parseColor("#6bcef5");
    private static final int COLOR_FEMALE = Color.parseColor("#f4989d");
    private static final int COLOR_INDETERMINATE = Color.parseColor("#c4db66");

    private int batchSize = 1;
    private int pixelSize = 3;
    private int inputSize = 64;
    private boolean inputAsRgb = true;
    private boolean floatNet = true;
    private int bytesPerChannel = 4;
    private Float[] imageMean = new Float[]{ 127.5f, 127.5f, 127.5f };
    private Float[] imageStd = new Float[]{ 127.5f, 127.5f, 127.5f };
    private FirebaseVisionFaceDetector detector;
    private String imageFileSavePath;
    private Uri imageFileUri;
    private Interpreter genderModel;

    @PluginMethod()
    public void initFaceRecognition(PluginCall call) {
        saveCall(call);

        notifyInitStatus(FaceRecInitStatus.Init);

        if (!hasPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) || !hasPermission(Manifest.permission.CAMERA)) {
            pluginRequestPermissions(new String[] {
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    Manifest.permission.CAMERA
            }, FaceRec.REQUEST_INIT);
            return;
        }

        if (call.hasOption("batchSize")) {
            Integer optBatchSize = call.getInt("batchSize");
            if (optBatchSize != null) {
                batchSize = optBatchSize;
            }
        }

        if (call.hasOption("pixelSize")) {
            Integer optPixelSize = call.getInt("pixelSize");
            if (optPixelSize != null) {
                pixelSize = optPixelSize;
            }
        }

        if (call.hasOption("inputSize")) {
            Integer optInputSize = call.getInt("inputSize");
            if (optInputSize != null) {
                inputSize = optInputSize;
            }
        }

        if (call.hasOption("inputAsRgb")) {
            Boolean optInputAsRgb = call.getBoolean("inputAsRgb");
            if (optInputAsRgb != null) {
                inputAsRgb = optInputAsRgb;
            }
        }

        if (call.hasOption("floatNet")) {
            Boolean optFloatNet = call.getBoolean("floatNet");
            if (optFloatNet != null) {
                floatNet = optFloatNet;
                bytesPerChannel = floatNet ? 4 : 1;
            }
        }

        String modelUrl = call.getString("modelUrl");

        try {
            URL url = new URL(modelUrl);
            String protocol = url.getProtocol();
            if (!protocol.equals("https")) {
                notifyInitError(INVALID_MODEL_URL_ERROR);
                call.error(INVALID_MODEL_URL_ERROR);
                return;
            }

            new FaceRecModelDownloadTask(this).execute(modelUrl, "gender_age_model", "model.tflite");
        } catch (MalformedURLException e) {
            notifyInitError(INVALID_MODEL_URL_ERROR);
            call.error(INVALID_MODEL_URL_ERROR);
        }
    }

    @PluginMethod()
    public void getPhoto(PluginCall call) {
        saveCall(call);

        FaceRecPhotoSource source = FaceRecPhotoSource.fromInt(call.getInt("source"));
        switch (source) {
            case Camera:
                getPhotoFromCamera(call);
                break;
            case Gallery:
                getPhotoFromGallery(call);
                break;
            default:
                call.error(INVALID_PHOTO_SOURCE);
        }
    }

    @Override
    protected void handleOnActivityResult(int requestCode, int resultCode, Intent data) {
        super.handleOnActivityResult(requestCode, resultCode, data);

        PluginCall savedCall = getSavedCall();

        if (savedCall == null) {
            return;
        }

        if (requestCode == REQUEST_IMAGE_CAPTURE) {
            processCameraImage(savedCall, data);
        } else if (requestCode == REQUEST_IMAGE_PICK) {
            processPickedImage(savedCall, data);
        }
    }

    @Override
    protected void handleRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.handleRequestPermissionsResult(requestCode, permissions, grantResults);

        Log.d(getLogTag(),"handling request perms result");

        if (getSavedCall() == null) {
            Log.d(getLogTag(),"No stored plugin call for permissions request result");
            return;
        }

        PluginCall savedCall = getSavedCall();

        for (int i = 0; i < grantResults.length; i++) {
            int result = grantResults[i];
            String perm = permissions[i];
            if(result == PackageManager.PERMISSION_DENIED) {
                Log.d(getLogTag(), "User denied camera permission: " + perm);
                savedCall.error(MISSING_INIT_PERMISSIONS);
                return;
            }
        }

        if (requestCode == REQUEST_INIT) {
            initFaceRecognition(savedCall);
        } else if (requestCode == REQUEST_IMAGE_CAPTURE) {
            getPhotoFromCamera(savedCall);
        }
    }

    protected void loadDownloadedModel(Boolean downloaded) {
        PluginCall call = getSavedCall();

        notifyInitStatus(FaceRecInitStatus.LoadingModels);

        String modelFilePath = getFilePath("gender_age_model", "model.tflite");
        File modelFile = new File(modelFilePath);

        if (!downloaded && !modelFile.exists()) {
            notifyInitError(MODEL_DOWNLOAD_ERROR);
            call.error(MODEL_DOWNLOAD_ERROR);
            return;
        }
        genderModel = new Interpreter(modelFile);

        try{
            FirebaseApp.getInstance();
        }
        catch (IllegalStateException e) {
            FirebaseApp.initializeApp(getContext());
        }

        FirebaseVisionFaceDetectorOptions options = new FirebaseVisionFaceDetectorOptions.Builder()
                .setPerformanceMode(FirebaseVisionFaceDetectorOptions.FAST)
                .setLandmarkMode(FirebaseVisionFaceDetectorOptions.NO_LANDMARKS)
                .setClassificationMode(FirebaseVisionFaceDetectorOptions.NO_CLASSIFICATIONS)
                .build();

        detector = FirebaseVision.getInstance().getVisionFaceDetector(options);

        notifyInitStatus(FaceRecInitStatus.Success);
        JSObject res = new JSObject();
        res.put("status", FaceRecInitStatus.Success.ordinal());
        call.success(res);
    }

    private void getPhotoFromCamera(PluginCall call) {
        if (hasPermission(Manifest.permission.CAMERA)) {
            if (!getContext().getPackageManager().hasSystemFeature(PackageManager.FEATURE_CAMERA)) {
                call.error(NO_CAMERA_ERROR);
                return;
            }

            Intent takePictureIntent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            if (takePictureIntent.resolveActivity(getContext().getPackageManager()) != null) {
                try {
                    String appId = getAppId();
                    File photoFile = createImageFile(getActivity(), false);
                    imageFileSavePath = photoFile.getAbsolutePath();
                    imageFileUri = FileProvider.getUriForFile(getActivity(), appId + ".fileprovider", photoFile);
                    takePictureIntent.putExtra(MediaStore.EXTRA_OUTPUT, imageFileUri);
                }
                catch (Exception ex) {
                    call.error(IMAGE_FILE_SAVE_ERROR, ex);
                    return;
                }

                startActivityForResult(call, takePictureIntent, REQUEST_IMAGE_CAPTURE);
            }
        } else {
            pluginRequestPermissions(new String[] {
                    Manifest.permission.CAMERA
            }, FaceRec.REQUEST_IMAGE_CAPTURE);
        }
    }

    private void getPhotoFromGallery(PluginCall call) {
        Intent intent = new Intent(Intent.ACTION_PICK);
        intent.setType("image/*");
        startActivityForResult(call, intent, REQUEST_IMAGE_PICK);
    }

    private void processCameraImage(PluginCall call, Intent data) {
        if (imageFileSavePath == null) {
            call.error(IMAGE_PROCESS_NO_FILE_ERROR);
            return;
        }

        Bitmap bitmap = getRotatedBitmap();
        if (bitmap == null) {
            call.error(IMAGE_PROCESS_NO_FILE_ERROR);
            return;
        }

        processImage(call, bitmap);
    }

    private void processPickedImage(PluginCall call, Intent data) {
        if (data == null) {
            call.error(NO_IMAGE_PICKED);
            return;
        }

        Uri u = data.getData();
        imageFileSavePath = getRealPathFromURI(getContext(), u);

        try {
            Bitmap bitmap = getRotatedBitmap();

            if (bitmap == null) {
                call.reject(UNABLE_TO_PROCESS_BITMAP);
                return;
            }

            processImage(call, bitmap);
        } catch (OutOfMemoryError err) {
            call.error(OUT_OF_MEMORY);
        }
    }

    private void processImage(PluginCall call, Bitmap bitmap) {
        final FaceRec plugin = this;
        final PluginCall pluginCall = call;
        Task<List<FirebaseVisionFace>> result = detector.detectInImage(FirebaseVisionImage.fromBitmap(bitmap));
        result.addOnSuccessListener(new OnSuccessListener<List<FirebaseVisionFace>>() {
            @Override
            public void onSuccess(@NonNull List<FirebaseVisionFace> faces) {
                plugin.processDetectedFaces(pluginCall, faces);
            }
        });
        result.addOnFailureListener(new OnFailureListener() {
            @Override
            public void onFailure(@NonNull Exception e) {
                plugin.processDetectedFaces(pluginCall, null);
            }
        });
    }

    private void processDetectedFaces(PluginCall call, List<FirebaseVisionFace> faces) {
        Bitmap bitmap = getRotatedBitmap();
        if (bitmap != null){
            File imageFile = new File(imageFileSavePath);
            Uri contentUri = Uri.fromFile(imageFile);
            JSArray resFaces = new JSArray();

            Bitmap taggedBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true);
            Canvas taggedCanvas = new Canvas(taggedBitmap);

            float lineWidth = (float)Math.max(3, Math.min(bitmap.getWidth(), bitmap.getHeight()) * 0.01);
            Paint linePaint = new Paint();
            linePaint.setStyle(Paint.Style.STROKE);
            linePaint.setStrokeWidth(lineWidth);

            int bitmapWidth = bitmap.getWidth();
            int bitmapHeight = bitmap.getHeight();

            if (faces != null && !faces.isEmpty()) {
                for (FirebaseVisionFace face : faces) {
                    Rect rect = face.getBoundingBox();
                    int width = rect.width();
                    int height = rect.height();
                    int size = Math.max(width, height);
                    int cropWidth = Math.min(bitmapWidth, size);
                    int cropHeight = Math.min(bitmapHeight, size);
                    int midCropWidth = Math.round(cropWidth / 2);
                    int midCropHeight = Math.round(cropHeight / 2);
                    int x = Math.min(bitmapWidth - cropWidth, Math.max(0, rect.centerX() - midCropWidth));
                    int y = Math.min(bitmapHeight - cropHeight, Math.max(0, rect.centerY() - midCropHeight));
                    float xScale = (float)inputSize / (float)cropWidth;
                    float yScale = (float)inputSize / (float)cropHeight;
                    Matrix matrix = new Matrix();
                    matrix.postScale(xScale, yScale);
                    Bitmap faceBitmap = Bitmap.createBitmap(bitmap, x, y, cropWidth, cropHeight, matrix, true);
                    ByteBuffer faceByteBuffer = convertBitmapToByteBuffer(faceBitmap);
                    faceBitmap.recycle();
                    float[][] result = new float[1][2];
                    genderModel.run(faceByteBuffer, result);
                    JSObject resFace = new JSObject();
                    resFace.put("x", x);
                    resFace.put("y", y);
                    resFace.put("width", width);
                    resFace.put("height", height);
                    JSObject resGender = new JSObject();
                    resGender.put("male", result[0][0]);
                    resGender.put("female", result[0][1]);
                    resFace.put("gender", resGender);
                    resFaces.put(resFace);

                    linePaint.setColor(getColor(result[0][0], result[0][1]));
                    taggedCanvas.drawRoundRect(rect.left, rect.top, rect.right, rect.bottom, lineWidth, lineWidth, linePaint);
                }
            } else {
                Bitmap faceBitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight());
                ByteBuffer faceByteBuffer = convertBitmapToByteBuffer(faceBitmap);
                float[][] result = new float[1][2];
                genderModel.run(faceByteBuffer, result);
                JSObject resFace = new JSObject();
                resFace.put("x", 0);
                resFace.put("y", 0);
                resFace.put("width", bitmap.getWidth());
                resFace.put("height", bitmap.getHeight());
                JSObject resGender = new JSObject();
                resGender.put("male", result[0][0]);
                resGender.put("female", result[0][1]);
                resFace.put("gender", resGender);
                resFaces.put(resFace);
            }

            JSObject result = new JSObject();

            result.put("originalImage", bitmapToBase64(bitmap, contentUri));
            bitmap.recycle();

            result.put("taggedImage", bitmapToBase64(taggedBitmap, contentUri));
            taggedBitmap.recycle();

            result.put("faces", resFaces);

            call.success(result);
        }
        else {
            call.error(IMAGE_PROCESS_NO_FILE_ERROR);
        }
    }

    private Bitmap getRotatedBitmap() {
        try {
            Bitmap bitmap = BitmapFactory.decodeFile(imageFileSavePath);
            ExifInterface exif = new ExifInterface(imageFileSavePath);
            int orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
            int rotation = orientationToRotation(orientation);
            if (rotation > 0) {
                Matrix matrix = new Matrix();
                matrix.preRotate(rotation);
                Bitmap adjustedBitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix, true);
                bitmap.recycle();
                bitmap = adjustedBitmap;
            }
            return bitmap;
        } catch (IOException ex) {
            return null;
        }
    }

    private int orientationToRotation(int orientation) {
        if (orientation == ExifInterface.ORIENTATION_ROTATE_90) { return 90; }
        if (orientation == ExifInterface.ORIENTATION_ROTATE_180) { return 180; }
        if (orientation == ExifInterface.ORIENTATION_ROTATE_270) { return 270; }
        return 0;
    }

    private JSObject bitmapToBase64(Bitmap bitmap, Uri u) {
        ByteArrayOutputStream bitmapOutputStream = new ByteArrayOutputStream();
        ExifWrapper exif = ImageUtils.getExifData(getContext(), bitmap, u);
        bitmap.compress(Bitmap.CompressFormat.JPEG, 90, bitmapOutputStream);
        byte[] byteArray = bitmapOutputStream.toByteArray();
        String encoded = Base64.encodeToString(byteArray, Base64.DEFAULT);

        JSObject exifJson = exif.toJson();
        exifJson.put(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
        JSObject data = new JSObject();
        data.put("base64Data", "data:image/jpeg;base64," + encoded);
        data.put("exif", exifJson);
        return data;
    }

    private int getColor(float male, float female) {
        if (male < 0.5) { return COLOR_MALE; }
        if (female < 0.5) { return COLOR_FEMALE; }
        return COLOR_INDETERMINATE;
    }

    private ByteBuffer convertBitmapToByteBuffer(Bitmap bitmap) {
        ByteBuffer byteBuffer = ByteBuffer.allocateDirect(bytesPerChannel * batchSize * inputSize * inputSize * pixelSize);
        byteBuffer.order(ByteOrder.nativeOrder());
        int[] intValues = new int[inputSize * inputSize];
        bitmap.getPixels(intValues, 0, bitmap.getWidth(), 0, 0, bitmap.getWidth(), bitmap.getHeight());
        int pixel = 0;
        for (int i = 0; i < inputSize; ++i) {
            for (int j = 0; j < inputSize; ++j) {
                final int val = intValues[pixel++];
                int first = inputAsRgb ? (val >> 16) & 0xFF : val & 0xFF; // red / blue
                int second = (val >> 8) & 0xFF; // green
                int third = inputAsRgb ? val & 0xFF : (val >> 16) & 0xFF; // blue / red
                if (floatNet) {
                    float normFirst = first - imageMean[0];
                    if (imageStd[0] != null) {
                        normFirst = normFirst / imageStd[0];
                    }
                    float normSecond = second - imageMean[1];
                    if (imageStd[1] != null) {
                        normSecond = normSecond / imageStd[1];
                    }
                    float normThird = third - imageMean[2];
                    if (imageStd[2] != null) {
                        normThird = normThird / imageStd[2];
                    }
                    byteBuffer.putFloat(normFirst);
                    byteBuffer.putFloat(normSecond);
                    byteBuffer.putFloat(normThird);
                } else {
                    byteBuffer.put((byte)(inputAsRgb ? (val >> 16) & 0xFF : val & 0xFF));
                    byteBuffer.put((byte)((val >> 8) & 0xFF)); // green
                    byteBuffer.put((byte)(inputAsRgb ? val & 0xFF : (val >> 16) & 0xFF)); // blue / red
                }
            }
        }
        return byteBuffer;
    }

    private File createImageFile(Activity activity, boolean saveToGallery) throws IOException {
        // Create an image file name
        String timeStamp = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date());
        String imageFileName = "JPEG_" + timeStamp + "_";
        File storageDir;
        if(saveToGallery) {
            Log.d(getLogTag(), "Trying to save image to public external directory");
            storageDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES);
        }  else {
            storageDir = activity.getExternalFilesDir(Environment.DIRECTORY_PICTURES);
        }

        File image = File.createTempFile(
                imageFileName,  /* prefix */
                ".jpg",         /* suffix */
                storageDir      /* directory */
        );

        return image;
    }

    private long getLastUpdate(URL url) {
        Context context = getContext();
        SharedPreferences sharedPref = context.getSharedPreferences(CACHE_PREFERENCES_NAME, Context.MODE_PRIVATE);
        return sharedPref.getLong("last-update-" + url.toString(), 0);
    }

    private void setLastUpdate(URL url) {
        Context context = getContext();
        SharedPreferences sharedPref = context.getSharedPreferences(CACHE_PREFERENCES_NAME, Context.MODE_PRIVATE);
        sharedPref.edit().putLong("last-update-" + url.toString(), System.currentTimeMillis()).apply();
    }

    private String getFilePath(String dest, String filename) {
        return new File(
                new File(getContext().getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS), dest),
                filename
        ).toString();
    }

    private void notifyInitStatus(FaceRecInitStatus status) {
        notifyInitStatus(status, null);
    }

    protected void notifyInitStatus(FaceRecInitStatus status, JSObject data) {
        if (data == null) {
            data = new JSObject();
        }
        data.put("status", status.ordinal());
        notifyListeners("faceRecInitStatusChanged", data);
    }

    private void notifyInitError(String error) {
        JSObject not = new JSObject();
        not.put("status", FaceRecInitStatus.Error.ordinal());
        if (error != null) {
            not.put("error", error);
        }
        notifyListeners("faceRecInitStatusChanged", not);
    }

    private String getRealPathFromURI(Context context, Uri contentUri) {
        Cursor cursor = null;
        try {
            if (contentUri != null) {
                String[] tempArray = {MediaStore.Images.Media.DATA};
                cursor = context.getContentResolver().query(contentUri, tempArray, null, null, null);
                if (cursor != null) {
                    int column_index = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA);
                    cursor.moveToFirst();
                    return cursor.getString(column_index);
                } else {
                    return null;
                }
            } else {
                return null;
            }
        } catch (Exception e) {
            Log.e(getLogTag(), e.getMessage());
            return null;
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
    }
}
