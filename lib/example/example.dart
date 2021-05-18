
import 'package:logging/logging.dart';
import 'package:script_engine/script_engine.dart';
import 'package:script_engine/src/actionCollect.dart';
import 'package:script_engine/src/logger.dart';

void main(List<String> args) async{
  initLogger(logLevel: Level.INFO);

  if(args.isNotEmpty) {
    String scriptPath=args[0];
    if(!scriptPath.startsWith("/"))scriptPath="${getCurrentPath()}/$scriptPath";

    Uri script = Uri.file(scriptPath);
    // String script = readFile(scriptPath);
    if(script!=null) {
      ScriptEngine se = ScriptEngine(script,extendSingleAction: myAction, debugMode: false);
      // Future.delayed(Duration(milliseconds: 500),()=>se.run());
      await se.init().then((value) =>se.run());
    }else{
      logger.warning("Cannot found script file");
      showUsage();
    }
  }else
    showUsage();

  // var mr=(await se.call("searchNovel",isMultiResult: false));
  // if(mr is List<String>) {
  //   for (String b in mr) {
  //     logger.info(b);
  //   }
  // }else logger.info(mr);
  //
  // logger.severe(getCurrentPath());
  // var uri=Uri.parse("asset:assets/config.json");
  // logger.fine("${uri.scheme} -- ${uri.path}");

//   print(RegExp("发表于([^<]*)<").firstMatch("""
// 发表于 2021-5-12 09:49
//      <a href="viewpro.php?uid=3341226" target="_blank">资料</a>
// 发表于 2021-5-13 09:49
//      <a href="viewpro.php?uid=3341226" target="_blank">资料</a>
//   """).group(1));
  // print("[$re]");
}

void showUsage(){
  logger.config("Usage : Cmd (scriptPath)");
  logger.info("Try again.");
}

Future<String?> myAction(String? value, dynamic ac,
{String? debugId, bool? debugMode})async{
  String ret="";
  switch(ac["action"]??""){
    case "lampFlash":
      print("lampFlash");
      ret=value??"";
      break;
    default:
      print("Unkown action ${ac["action"]??""}");
  }
  return ret;
}