package io.gnucoop.facerec.plugin;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.AsyncTask;
import android.os.Environment;

import com.getcapacitor.JSObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.MalformedURLException;
import java.net.URL;

import javax.net.ssl.HttpsURLConnection;

public class FaceRecModelDownloadTask extends AsyncTask<String, JSObject, Boolean> {
    private static final int BUFFER_SIZE = 4096;

    private FaceRec plugin;

    public FaceRecModelDownloadTask(FaceRec plugin) {
        this.plugin = plugin;
    }

    @Override
    protected Boolean doInBackground(String... strings) {
        String modelUrl = strings[0];
        String dest = strings[1];
        String filename;
        if (strings.length < 3) {
            filename = modelUrl.substring(modelUrl.lastIndexOf("/") + 1, modelUrl.length());
        } else {
            filename = strings[2];
        }

        URL url;
        try {
            url = new URL(modelUrl);
        } catch (MalformedURLException e) {
            return false;
        }

        String filePath = getFilePath(dest, filename);

        try {
            HttpsURLConnection conn = (HttpsURLConnection) url.openConnection();
            long currentTime = System.currentTimeMillis();
            long expires = conn.getHeaderFieldDate("Expires", currentTime);
            long lastModified = conn.getHeaderFieldDate("Last-Modified", currentTime);
            long lastUpdateTime = getLastUpdate(url);
            if (lastModified > lastUpdateTime || expires < lastUpdateTime) {
                int responseCode = conn.getResponseCode();
                if (responseCode == HttpsURLConnection.HTTP_OK) {
                    InputStream inputStream = conn.getInputStream();
                    File file = new File(filePath);
                    File parent = file.getParentFile();
                    if (!parent.exists()) {
                        boolean parentCreated = parent.mkdirs();
                        if (!parentCreated) {
                            return false;
                        }
                    }
                    if (!file.exists()) {
                        boolean fileCreated = file.createNewFile();
                        if (!fileCreated) {
                            return false;
                        }
                    }

                    JSObject dlProgress = new JSObject();
                    int fileLen = conn.getContentLength();
                    int readLen = 0;

                    if (fileLen > -1) {
                        dlProgress.put("progress", 0f);
                    }

                    plugin.notifyInitStatus(FaceRecInitStatus.DownloadingModels, dlProgress);

                    FileOutputStream outputStream = new FileOutputStream(file);

                    int bytesRead;
                    byte[] buffer = new byte[BUFFER_SIZE];
                    while ((bytesRead = inputStream.read(buffer)) != -1) {
                        outputStream.write(buffer, 0, bytesRead);
                        readLen += bytesRead;
                        if (fileLen > 0) {
                            dlProgress.put("progress", (float)readLen / fileLen);
                            plugin.notifyInitStatus(FaceRecInitStatus.DownloadingModels, dlProgress);
                        }
                    }

                    outputStream.close();
                    inputStream.close();

                    setLastUpdate(url);

                    return true;
                }
                return false;
            }
            return true;
        } catch(IOException e) {
            return false;
        }
    }

    @Override
    protected void onPostExecute(Boolean result) {
        plugin.loadDownloadedModel(result);
    }

    private String getFilePath(String dest, String filename) {
        return new File(
                new File(plugin.getContext().getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS), dest),
                filename
        ).toString();
    }

    private long getLastUpdate(URL url) {
        Context context = plugin.getContext();
        SharedPreferences sharedPref = context.getSharedPreferences(FaceRec.CACHE_PREFERENCES_NAME, Context.MODE_PRIVATE);
        return sharedPref.getLong("last-update-" + url.toString(), 0);
    }

    private void setLastUpdate(URL url) {
        Context context = plugin.getContext();
        SharedPreferences sharedPref = context.getSharedPreferences(FaceRec.CACHE_PREFERENCES_NAME, Context.MODE_PRIVATE);
        sharedPref.edit().putLong("last-update-" + url.toString(), System.currentTimeMillis()).apply();
    }
}
