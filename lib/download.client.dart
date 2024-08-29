import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_download_audio_and_video/types.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadFile {
  String id;
  String downloadUrl;
  String ext;
  String dirPath;
  String filePath;
  String? taskId;
  DownloadTaskStatus? taskStatus;
  int? taskProgress;
  bool? savedToGallery;

  DownloadFile(
      {required this.id,
      required this.downloadUrl,
      required this.ext,
      required this.dirPath,
      required this.filePath,
      this.taskId,
      this.taskStatus,
      this.taskProgress,
      this.savedToGallery});
}

class DownloadClient {
  static get localPath async => (Platform.isIOS
          ? await getApplicationDocumentsDirectory()
          : await getExternalStorageDirectory())
      ?.path;

  // _port is used to communicate between the isolates
  final ReceivePort _port = ReceivePort();

  List<DownloadFile> _downloadFiles = [];

  String dirPath = '';

  void bindBackgroundIsolate(Function(String, int, int) updateProgress) async {
    final portSuccess = IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');

    if (!portSuccess) {
      unbindBackgroundIsolate();
      bindBackgroundIsolate(updateProgress);
      return;
    } else {
      _port.listen((message) {
        String id = message[0];
        int status = message[1];
        int progress = message[2];

        updateProgress(id, status, progress);

        int fileindex = _downloadFiles.indexWhere((file) => file.taskId == id);

        if (fileindex != -1) {
          _downloadFiles[fileindex].taskStatus =
              DownloadTaskStatus.fromInt(status);
          _downloadFiles[fileindex].taskProgress = progress;
        }
      });

      FlutterDownloader.registerCallback(progressCallback);
    }
  }

  void unbindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  static progressCallback(String id, int status, int progress) {
    final SendPort? send =
        IsolateNameServer.lookupPortByName('downloader_send_port');

    send?.send([id, status, progress]);
  }

  Future download({
    required AssetType assetType,
    required DownloadFile file,
  }) async {
    if (assetType == AssetType.video) {
      dirPath = "${(await localPath)}/videoFiles";
    } else {
      dirPath = "${(await localPath)}/audioFiles";
    }

    file.dirPath = dirPath;

    String fileName = "${file.id}.${file.ext}";

    String filePath = "$dirPath/$fileName";

    await Directory(dirPath).create(recursive: true).then((value) async {
      String? taskId = await FlutterDownloader.enqueue(
        url: file.downloadUrl,
        savedDir: dirPath,
        fileName: fileName,
        saveInPublicStorage: Platform.isAndroid && assetType == AssetType.audio,
      );

      if (taskId != null) {
        file.taskId = taskId;
        file.filePath = filePath;
      }
    });
  }

  Future cancelAll() async {
    await FlutterDownloader.cancelAll();
  }

  Future<bool> checkForPermissionToSaveToGallery() async {
    bool hasAccess = await Gal.hasAccess();

    if (!hasAccess) {
      bool response = await Gal.requestAccess();

      if (!response) {
        // TODO: TOAST
        return response;
      }
    }

    return hasAccess;
  }

  Future<bool> saveToGallery(DownloadFile file) async {
    try {
      await Gal.putVideo(file.filePath);
      return true;
    } on GalException catch (e) {
      return false;
    }
  }
}
