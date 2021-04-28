// import 'dart:developer';
import 'package:logging/logging.dart';
import 'package:console/console.dart';

final logger = Logger("System");

void initLogger({Level logLevel = Level.FINE}) {
  const String colorEnd="{{@end}}";
  const String logNameColor="{{@dark_blue}}";
  Logger.root.level = logLevel;
  Logger.root.onRecord.listen((event) {
    String color = "{{@yellow}}";
    final String colorEnd = "{{@end}}";
    switch (event.level.value) {
      case 0:
      case 300:
        color = "{{@light_gray}}";
        break;
      case 400:
        color = "{{@light_magenta}}";
        break;
      case 500:
        color = "{{@green}}";
        break;
      case 700:
      case 800:
        color = "{{@yellow}}";
        break;
      case 900:
        color = "{{@magenta}}";
        break;
      case 1000:
        color = "{{@red}}";
        break;
      case 1200:
      default:
        color = "{{@yellow}}";
        break;
    }
    if (event.level >= logLevel)
      print(format(
          "${DateTime.now().toString()} - $logNameColor[${event.loggerName}]$colorEnd - $color${event.level.toString()}$colorEnd : $color${event.message}$colorEnd",style: VariableStyle.DOUBLE_BRACKET));
    // print(
    //     "${DateTime.now().toString()} - [${event.loggerName}] - ${event.level.toString()} : ${event.message}");
    // log("${DateTime.now().toString()} -- ${event.level.toString()} : ${event.message}",time:DateTime.now(),name: event.loggerName,level: 0);
  });
}

void largeLog(dynamic msg, {Level level = Level.FINER}) {
  String str;
  final int maxPrintLength = 511;

  if (!(msg is String)) {
    str = msg.toString();
  } else {
    str = msg;
  }

  for (String oneLine in str.split("\n")) {
    while (oneLine.length > maxPrintLength) {
      logger.log(level, oneLine.substring(0, maxPrintLength));
      oneLine = oneLine.substring(maxPrintLength);
    }
    logger.log(level, oneLine);
  }
}
