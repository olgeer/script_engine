import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:script_engine/script_engine.dart';
import 'package:script_engine/src/actionCollect.dart';
import 'package:script_engine/src/logger.dart';

void main(List<String> args) async {
  initLogger(logLevel: Level.INFO);

  if (args.isNotEmpty) {
    String scriptPath = args[0];
    if (!scriptPath.startsWith("/"))
      scriptPath = "${getCurrentPath()}/$scriptPath";

    Uri script = Uri.file(scriptPath);
    // String script = readFile(scriptPath);
    // if (script != null) {
      ScriptEngine se = ScriptEngine(
          scriptSource: script,
          extendSingleAction: myAction,
          debugMode: true,
          onPause: (v, a, r, i, se) async {
            logger.info("\nvalue:$v\naction:$a\nret:$r\ndebugid:$i");
          }
      );
      // Future.delayed(Duration(milliseconds: 500),()=>se.run());
      String? result;
      await se.init().then((value) async => result = await se.run());
      logger.info(result);
    // } else {
    //   logger.warning("Cannot found script file");
    //   showUsage();
    // }
  } else {
    showUsage();

    // print((await Dio().post("https://www.shutxt.com/e/search/index.php",
    //         data:"keyboard=80&show=title",
    //         queryParameters: {},
    //         options: Options(
    //           headers: {"Content-Type":"application/x-www-form-urlencoded"},
    //             responseType: ResponseType.bytes,
    //             )))
    //     .statusCode);
  }
}

void showUsage() {
  logger.config("Usage : Cmd (scriptPath)");
  logger.info("Try again.");
}

Future<String?> myAction(String? value, Map<String,dynamic> ac,ScriptEngine se,
    String? debugId, bool? debugMode) async {
  String ret = "";
  switch (ac["action"] ?? "") {
    case "extraaction1":
      ret = "${value??""}-${se.exchgValue(ac["params"])??""}";
      break;
    default:
      print("Unkown action ${ac["action"] ?? ""}");
  }
  return ret;
}
