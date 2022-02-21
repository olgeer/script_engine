import 'dart:convert';
import 'dart:io';
import 'dart:math';
// import 'package:charset_converter/charset_converter.dart';
import 'package:dio/adapter.dart';
import 'package:html/dom.dart';
import 'package:dio/dio.dart';
import 'package:script_engine/src/logger.dart';

typedef FutureCall = Future<Response?> Function();
enum RequestMethod { get, post }

Map<String,dynamic> cmdLowcase(dynamic ac){
  Map<String,dynamic> newAc=Map.castFrom(ac as Map<String,dynamic>);

  var oldKeys=newAc.keys.toList();
  for(String oldKey in oldKeys){
    newAc.putIfAbsent(oldKey.toLowerCase(), () => newAc.remove(oldKey));
  }

  return newAc;
}

String strLowcase(dynamic str){
  // String ret=((str as String)??"").toLowerCase();
  return (str as String).toLowerCase();
}

List<String> domList2StrList(List<Element> domList) {
  List<String> retList = [];
  for (Element e in domList) {
    retList.add(e.outerHtml);
  }
  return retList;
}

Future<Response?> callWithRetry(
    {int retryTimes: 3, int seconds = 2, required FutureCall retryCall}) async {
  Response? resp;
  do {
    retryTimes--;
    try {
      resp = await retryCall();
      //await Future.delayed(Duration(milliseconds: downloadSleepDuration));
    } catch (e) {
      print("Response error[$retryTimes]:$e");
      await Future.delayed(Duration(seconds: seconds));
    }
  } while (resp == null && retryTimes > 0);
  return resp;
}

String getCurrentPath() {
  return Directory.current.path;
}

Future<Response?> getUrlFile(String url,
    {int retry = 3, int seconds = 3, bool debugMode = false}) async {
  Response? tmp;
  Dio? dio;

  if (dio == null)
    dio = Dio(BaseOptions(
      connectTimeout: 5000,
      receiveTimeout: 5000,
    ));

  if (debugMode)
    dio.interceptors.add(LogInterceptor(request: true, responseHeader: true));

  do {
    try {
      tmp = await dio.get(url,
          options: Options(responseType: ResponseType.bytes));
    } catch (e) {
      if (e is DioError) {
        // logger.warning("DioErrorType : ${e.type.toString()}");
        switch (e.type) {
          case DioErrorType.receiveTimeout:
            logger.warning("Receive Timeout! When get file $url . Retry ...");
            await Future.delayed(Duration(seconds: seconds));
            break;
          case DioErrorType.connectTimeout:
            logger.warning("Connect Timeout! When get file $url . Retry ...");
            await Future.delayed(Duration(seconds: seconds));
            break;
          case DioErrorType.response:
            switch (e.response?.statusCode??505) {
              case 404:
                logger.warning("$url not found. [404]");
                retry = 0;
                break;
              case 500:
                logger.warning("$url background service error. [500]");
                retry = 0;
                break;
              default:
                logger.warning(
                    "StatusCode:[${e.response?.statusCode??"505"}] get file [$url] error:${e.message} ");
                await Future.delayed(Duration(seconds: seconds));
                break;
            }
            break;
          default:
            logger.warning(
                "DioErrorType : ${e.type}], get file [$url] error : ${e.message}");
            await Future.delayed(Duration(seconds: seconds));
        }
      }
    }
  } while ((tmp == null || (tmp.statusCode??0) != 200) && --retry > 0);

  return (tmp?.statusCode??0) == 200 ? tmp : null;
}

Future<String?> saveUrlFile(String url,
    {String? saveFileWithoutExt,
    FileMode fileMode=FileMode.write,
    int retry = 3,
    int seconds = 3}) async {
  // if (tmpResp.data > 0) {
  List<String> tmpSpile = url.split("//")[1].split("/");
  String? fileExt;
  if (tmpSpile.last.length > 0 && tmpSpile.last.split(".").length > 1) {
    if (saveFileWithoutExt == null || saveFileWithoutExt.length == 0) {
      saveFileWithoutExt = getCurrentPath() + "/" + tmpSpile.last.split(".")[0];
    }
    fileExt = tmpSpile.last.split(".")[1];
  } else {
    if (saveFileWithoutExt == null || saveFileWithoutExt.length == 0) {
      saveFileWithoutExt = genKey(lenght: 12);
    }
  }

  File urlFile = File("$saveFileWithoutExt.${fileExt ?? ""}");
  if (urlFile.existsSync() && fileMode==FileMode.write) {
    urlFile.deleteSync();
  }
  if (!urlFile.existsSync()) {
    Response? tmpResp = await getUrlFile(url, retry: retry, seconds: seconds);
    if (tmpResp != null) {
      if (fileExt == null) {
        fileExt = tmpResp.headers.value('Content-Type')?.split("/")[1];
        urlFile = File("$saveFileWithoutExt.${fileExt ?? ""}");
      }

      logger.finer("File:${urlFile.path}");

      urlFile.createSync(recursive: true);
      urlFile.writeAsBytesSync(tmpResp.data.toList(),
          mode: fileMode, flush: true);

      logger.fine("Save $url to ${urlFile.path} is OK !");
    } else {
      logger.warning("--Download $url is failed !");
      return null;
    }
  } else {
    logger.fine("Not save $url to ${urlFile.path} because it was existed !");
  }
  return urlFile.path;
}

Future<String?> getHtml(String sUrl,
    {Map<String, dynamic>? headers,
    Map<String, dynamic>? queryParameters,
    String? body,
    RequestMethod method = RequestMethod.get,
    Encoding encoding = utf8,
    int retryTimes = 3,
    int seconds = 5,
    String? debugId,
    bool debugMode = false}) async {
  Dio? dio;
  String? html;
  // Logger().debug("getHtml-[${debugId ?? ""}]", "Ready getHtml: [$sUrl]");
  // logger.fine("$body");

  if (dio == null)
    dio = Dio(BaseOptions(
      connectTimeout: 5000,
      receiveTimeout: 3000,
      sendTimeout: 2000,
    ));

  if (debugMode) {
    dio.interceptors.add(LogInterceptor(request: true, responseHeader: true));
  }

  //解决ssl证书过期无法访问的问题
  (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate = (client){
    client.badCertificateCallback=(cert, host, port){
      return true;
    };
  };

  Response? listResp = await callWithRetry(
      seconds: seconds,
      retryTimes: retryTimes,
      retryCall: () async {
        try {
          if (method == RequestMethod.get) {
            return await dio!.get(sUrl,
                queryParameters: queryParameters,
                options: Options(
                    headers: headers, responseType: ResponseType.bytes));
          } else {
            return await dio!.post(sUrl,
                // queryParameters: queryParameters,
                options: Options(
                    headers: headers,
                    responseType: ResponseType.bytes,
                    // contentType: "application/x-www-form-urlencoded"
                    ),
                data: body);
          }
        } catch (e) {
          if (e is DioError && e.response?.statusCode == 302 && e.response?.headers["location"]!=null) {
            try {
              String newUrl =e.response!.headers["location"]!.first;
              newUrl="${newUrl.contains("http")?"":getDomain(sUrl)}$newUrl";
              logger.finer("status code:302 and redirect to $newUrl");
              return await dio!.get(newUrl,
                  options: Options(responseType: ResponseType.bytes));
            } catch (e) {
              print(e);
              return null;
            }
          } else {
            // print(e);
            return null;
          }
        }
      });

  if (listResp!=null && listResp.statusCode == 200) {
    try {
      html = encoding.decode(listResp.data);
    } catch (e) {
      // if(encoding.name.contains("gb") && (Platform.isAndroid||Platform.isIOS)){
      //   html = await CharsetConverter.decode("GB18030",listResp.data);
      // }else{
        logger.warning("Charset decode error");
        return null;
      // }
    }
  }

  return html;
}

String genKey({int lenght = 24}) {
  const randomChars = [
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F'
  ];
  String key = "";
  for (int i = 0; i < lenght; i++) {
    key += randomChars[Random().nextInt(randomChars.length)];
  }
  return key;
}

String getDomain(String url) {
  return url.replaceAll(url.split("/").last, "");
}

String? readFile(dynamic file) {
  late File readFile;
  if (file is String) readFile = File(file);
  if (file is File) readFile = file;
  if (readFile.existsSync()) {
    try {
      return readFile.readAsStringSync();
    } catch (e) {
      return null;
    }
  } else
    return null;
}

void saveFile(String filename, String content,
    {FileMode fileMode = FileMode.append, Encoding encoding = utf8}) {
  logger.finer("Save file:$filename");

  File saveFile = File(filename);

  if (!saveFile.existsSync()) saveFile.createSync(recursive: true);

  saveFile.writeAsStringSync(content,
      mode: fileMode, encoding: encoding, flush: true);
}

String shortString(String content, {int limit = 200}) {
  String ret = content;
  if (ret.length > limit) ret = "${ret.substring(0, limit)} ... ";
  return ret;
}
