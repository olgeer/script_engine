
import 'package:logging/logging.dart';
import 'package:script_engine/script_engine.dart';
import 'package:script_engine/src/actionCollect.dart';
import 'package:script_engine/src/logger.dart';

void main(List<String> args) async{
  initLogger(logLevel: Level.INFO);

  if(args.isNotEmpty) {
    String scriptPath=args[0];
    if(!scriptPath.startsWith("/"))scriptPath="${getCurrentPath()}/$scriptPath";

    String script = readFile(scriptPath);
    if(script!=null) {
      ScriptEngine se = ScriptEngine(script, debugMode: false);
      se.run();
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
}

void showUsage(){
  logger.config("Usage : Cmd (scriptPath)");
  logger.info("Try again.");
}