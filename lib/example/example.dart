
import 'package:logging/logging.dart';
import 'package:script_engine/example/scriptObj.dart';
import 'package:script_engine/script_engine.dart';
import 'package:script_engine/src/logger.dart';

void main() async{
  initLogger(logLevel: Level.FINER);
  ScriptEngine se=ScriptEngine(scriptStr,debugMode: true);
  // se.run();
  var mr=(await se.call("searchNovel",isMultiResult: false));
  if(mr is List<String>) {
    for (String b in mr) {
      logger.info(b);
    }
  }else logger.info(mr);
  // var uri=Uri.parse("asset:assets/config.json");
  // logger.fine("${uri.scheme} -- ${uri.path}");
}