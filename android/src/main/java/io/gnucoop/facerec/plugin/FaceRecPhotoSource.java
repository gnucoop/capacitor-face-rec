package io.gnucoop.facerec.plugin;

public enum FaceRecPhotoSource {
  Camera,
  Gallery;

  public static FaceRecPhotoSource fromInt(int value) {
    if (value == 0) {
      return FaceRecPhotoSource.Camera;
    }
    if (value == 1) {
      return FaceRecPhotoSource.Gallery;
    }
    return null;
  }
}
