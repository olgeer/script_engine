import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:html/dom.dart';
import 'package:dio/dio.dart';
import 'package:script_engine/src/logger.dart';

typedef FutureCall = Future<Response> Function();
enum RequestMethod { get, post }

List<String> domList2StrList(List<Element> domList) {
  List<String> retList = [];
  for (Element e in domList) {
    retList.add(e.outerHtml);
  }
  return retList;
}

Future<Response> callWithRetry(
    {int retryTimes: 3, int seconds = 2, FutureCall retryCall}) async {
  Response resp;
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

Future<String> getHtml(String sUrl,
    {Map<String, dynamic> headers,
    Map<String, dynamic> queryParameters,
    String body,
    RequestMethod method = RequestMethod.get,
    Encoding encoding = utf8,
    int retryTimes = 3,
    int seconds = 5,
    String debugId,
    bool debugMode = true}) async {
  Dio dio;
  String html;
  // Logger().debug("getHtml-[${debugId ?? ""}]", "Ready getHtml: [$sUrl]");

  if (dio == null)
    dio = Dio(BaseOptions(
      connectTimeout: 5000,
      receiveTimeout: 3000,
    ));

  if (debugMode)
    dio.interceptors.add(LogInterceptor(request: true, responseHeader: true));

  if (sUrl != null) {
    Response listResp = await callWithRetry(
        seconds: seconds,
        retryTimes: retryTimes,
        retryCall: () async {
          try {
            if (method == RequestMethod.get) {
              return await dio.get(sUrl,
                  queryParameters: queryParameters,
                  options: Options(
                      headers: headers, responseType: ResponseType.bytes));
            } else {
              return await dio.post(sUrl,
                  queryParameters: queryParameters,
                  options: Options(
                      headers: headers, responseType: ResponseType.bytes),
                  data: body);
            }
          } catch (e) {
            if (e is DioError && e.response.statusCode == 302) {
              try {
                String newUrl =
                    "${getDomain(sUrl)}${e.response.headers["location"].first}";
                logger.finer("status code:302 and redirect to $newUrl");
                return await dio.get(newUrl,
                    options: Options(responseType: ResponseType.bytes));
              } catch (e) {
                print(e);
                return null;
              }
            } else {
              print(e);
              return null;
            }
          }
        });

    if (listResp?.statusCode == 200) {
      html = encoding.decode(listResp.data);
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
  assert(url != null);
  return url.replaceAll(url.split("/").last, "");
}

String readFile(dynamic file) {
  File readFile;
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
  File saveFile = File(filename);
  if (!saveFile.existsSync()) saveFile.createSync(recursive: true);

  saveFile.writeAsStringSync(content ?? "",
      mode: fileMode, encoding: encoding, flush: true);
}

String shortString(String content, {int limit = 200}) {
  String ret = content??"";
  if (ret.length > limit) ret = "${ret.substring(0, limit)} ... ";
  return ret;
}
