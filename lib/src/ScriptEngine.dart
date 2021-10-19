import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart';
import 'package:html/dom.dart';
import 'package:logging/logging.dart';
import 'package:xpath_parse/xpath_selector.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'actionCollect.dart';
import 'HtmlCodec.dart';

typedef singleAction = Future<String?> Function(String? value, dynamic ac,
    {String? debugId, bool? debugMode});
typedef multiAction = Future<List<String?>> Function(
    List<String?> value, dynamic ac,
    {String? debugId, bool? debugMode});
typedef valueProvider = String Function(String exp);
typedef actionEvent = Future<void> Function(
    dynamic value, dynamic ac, dynamic ret, String debugId,ScriptEngine se);
enum ScriptEngineState { Initing, Ready, Running, Done, Pause }

class ScriptEngine {
  Map<String, dynamic> tValue = {}; //配置运行时临时变量表
  List<String?> tStack = []; //配置运行时堆栈
  Map<String, dynamic>? globalValue;
  Map<String, dynamic> functions = {};
  bool debugMode;

  late dynamic scriptSource;
  String? script;
  late Map<String, dynamic> scriptJson;
  late String processName;

  singleAction? extendSingleAction;
  multiAction? extendMultiAction;
  valueProvider? extendValueProvide;

  actionEvent? onAction;
  actionEvent? onPause;
  void Function(ScriptEngineState s)? onScriptEngineStateChange;

  final Logger logger = Logger("ScriptEngine");

  final String MULTIRESULT = "multiResult";
  final String SINGLERESULT = "singleResult";
  final String RETURNCODE = "returnCode";
  bool isExit = false;
  ScriptEngineState? state;

  ///初始化json脚本引擎，暂时一个脚本对应一个引擎，拥有独立的变量及堆栈空间
  ///scriptSource可以是String，Uri，File等类型，指向json脚本内容
  ScriptEngine(this.scriptSource,
      {this.extendSingleAction,
      this.extendMultiAction,
      this.extendValueProvide,
      this.onAction,
        this.onPause,
      this.onScriptEngineStateChange,
      this.debugMode = false})
      : assert(scriptSource != null);

  Future<ScriptEngine> init() async {
    await initScript(scriptSource);
    return this;
  }

  static Future<String?> loadScript(dynamic scriptSrc) async {
    String? s;
    if (scriptSrc is Uri) {
      if (scriptSrc.isScheme("file")) s = readFile(File(scriptSrc.path));
      if (scriptSrc.isScheme("https") || scriptSrc.isScheme("http"))
        s = await getHtml(scriptSrc.toString());
    }
    if (scriptSrc is File) {
      s = readFile(scriptSrc);
    }
    if (scriptSrc is String) {
      if (scriptSrc.startsWith("http")) {
        s = await getHtml(scriptSrc);
      } else if (scriptSrc.startsWith("file")) {
        s = readFile(File(Uri.parse(scriptSrc).path));
      } else {
        s = scriptSrc;
      }
    }
    return s;
  }

  Future<void> initScript(dynamic scriptSrc) async {
    if (state == null) {
      state = ScriptEngineState.Initing;
      if (onScriptEngineStateChange != null) onScriptEngineStateChange!(state!);
      try {
        script = await loadScript(scriptSrc);
        scriptJson = json.decode(script ?? "{}");
      } catch (e) {
        print(e);
        scriptJson = {};
      }

      // if (scriptJson["beginSegment"] == null) {
      //   logger.warning("找不到[beginSegment]段落，执行结束！");
      //   return;
      // }

      processName = scriptJson["processName"] ?? "DefaultProcess";

      if (scriptJson["globalValue"] != null) {
        globalValue = Map.castFrom(scriptJson["globalValue"] ?? {});
        reloadGlobalValue();
      }

      functions = Map.castFrom(scriptJson["functionDefine"] ?? {});

      state = ScriptEngineState.Ready;
      if (onScriptEngineStateChange != null) onScriptEngineStateChange!(state!);
    } else {
      logger.fine("Script Engine had inited !");
    }
  }

  ///直接执行脚本，所有处理均包含在脚本内，对最终结果不太关注
  Future<String?> run({bool stepByStep = false}) async {
    if (state == null) await init();
    // while (state == ScriptEngineState.Initing) {
    //   Future.delayed(Duration(milliseconds: 500));
    // }
    if (scriptJson["beginSegment"] != null) {
      state = ScriptEngineState.Running;
      if (onScriptEngineStateChange != null) onScriptEngineStateChange!(state!);

      String? ret = await singleProcess("", scriptJson["beginSegment"]);

      state = ScriptEngineState.Done;
      if (onScriptEngineStateChange != null) onScriptEngineStateChange!(state!);
      return ret;
    } else
      return null;
  }

  void stop() async {
    isExit = true;
  }

  ///调用某函数方法，期待脚本返回中间结果，以便后续程序使用
  ///isMultiResult参数为true时，返回最后一组结果列表，为false时，返回最终的字符串结果
  Future call(String functionName, {bool isMultiResult = false}) async {
    await singleProcess("", functions[functionName]);
    return isMultiResult ? getValue(MULTIRESULT) : getValue(SINGLERESULT);
  }

  void clear() {
    tValue.clear();
    tStack.clear();
    reloadGlobalValue();
    logger.fine("$processName is clear.");
  }

  void reloadGlobalValue() {
    globalValue?.forEach((key, value) {
      setValue(key, value);
    });
  }

  String? exchgValue(String? exp) {
    final RegExp valueExp = RegExp('{([^}]+)}');
    final int MAXLOOP = 100;
    int loopTime = 1;
    String? ret = exp;

    if (exp != null) {
      while (valueExp.hasMatch(ret!) && loopTime < MAXLOOP) {
        loopTime++;

        String valueName = valueExp.firstMatch(ret)!.group(1)!;
        String? repValue;
        switch (valueName) {
          case "system.platform":
            repValue = Platform.operatingSystem;
            break;
          case "system.platformVersion":
            repValue = Platform.operatingSystemVersion;
            break;
          case "system.currentdir":
            repValue = getCurrentPath();
            break;
          case "system.now":
            repValue = DateTime.now().toString();
            break;
          case "system.date":
            repValue = DateTime.now().toString().split(" ")[0];
            break;
          default:
            var v = getValue(valueName);
            if (v == null) {
              if (extendValueProvide != null)
                repValue = extendValueProvide!(valueName);
              break;
            } else if (v is String) {
              repValue = v;
            } else
              repValue = v.toString();
            break;
        }
        ret = ret.replaceFirst(valueExp, repValue ?? "");
      }
      if (loopTime > MAXLOOP) logger.warning("Dead loop ! exp=[$ret]");
    }
    if (debugMode) logger.fine("Exchange value [$exp] to [$ret]");
    return ret;
  }

  void setValue(String key, dynamic value) {
    // if (tValue[key] != null) {
    tValue[key] = value;
    // } else {
    //   tValue.putIfAbsent(key, () => value);
    // }
    if (debugMode) logger.finer("Set value($key) to $value");
  }

  String removeValue(String key) => tValue.remove(key);

  dynamic getValue(String key) => tValue[key];

  Future<String?> singleProcess(String? value, dynamic procCfg) async {
    if (procCfg != null) {
      String debugId = genKey(lenght: 8);

      for (var act in procCfg ?? []) {
        if (isExit) break;
        String? preErrorProc = value;
        setValue("this", value);
        value = await action(value, act, debugId: debugId);
        if (value == null && (getValue(RETURNCODE) ?? 1) != 0) {
          if (debugMode)
            logger.fine(
                "--$debugId--[Return null,Abort this singleProcess! Please check singleAction($act,$preErrorProc)");
          break;
        }
      }
      // tValue.clear(); //确保产生的变量仅用于本process内
      // tStack.clear();
      setValue(SINGLERESULT, value);
      return value;
    } else {
      if (debugMode)
        logger.fine(
            "----[procCfg is null,Abort this singleProcess! Please check !");
      return null;
    }
  }

  Future<String?> action(String? value, dynamic ac,
      {String debugId = ""}) async {
    String? ret;
    bool refreshValue = true;
    if (debugMode) logger.fine("--$debugId--💃action($ac)");
    if (debugMode) logger.finest("--$debugId--value : $value");

    try {
      switch (ac["action"]) {
        case "pause":
          if(onPause!=null) {
            state = ScriptEngineState.Pause;
            onPause!(value, ac, ret, debugId,this);
            while(state==ScriptEngineState.Pause){
              sleep(Duration(seconds: 1));
            }
          }

          refreshValue = false;
          break;
        case "print":
          //           {
          //             "action": "print",
          //             "value": "url"   //*
          //           }
          logger.info(exchgValue(ac["value"]) ?? value);
          refreshValue = false;
          break;
        case "replace":
          //             {
          //               "action": "replace",
          //               "from": "<(\\S+)[\\S| |\\n|\\r]*?>[^<]*</\\1>",
          //               "to": ""
          //             },
          ret =
              value?.replaceAll(RegExp(ac["from"]), exchgValue(ac["to"]) ?? "");
          break;
        case "substring":
          //             {
          //               "action": "substring",
          //               "start": 2,  // 为null 则 从0开始，如果为 负数 则从后面算起，如 "abcde" ,-2则指从'd'起
          //               "end": 10,   // 为null 则 到结尾，当end值小于begin值时，两值对调，如为负数则从开始算起
          //               "length": 4  // 当end为null时，解释此参数，如亦为null则忽略此逻辑
          //             },
          if (value != null) {
            int start = ac["start"] ?? 0;
            int? end = ac["end"];
            int? length = ac["length"];
            if (end == null && length == null) {
              ret = value.substring(start);
            } else {
              if (start < 0) start = value.length + start;
              if (start < 0 || start > value.length) start = 0;

              if (end == null) end = start + length!;

              if (end < 0) end = value.length + end;
              if (end < start) {
                int temp = start;
                start = end;
                end = temp;
              }
              ret = value.substring(start, end);
            }
          } else {
            ret = value;
          }
          break;
        case "concat":
          //           {
          //             "action": "concat",
          //             "front": "<table>",
          //             "back": "</table>"
          //           }
          String f = ac["front"] ?? "";
          String b = ac["back"] ?? "";
          f = exchgValue(f)!;
          b = exchgValue(b)!;
          ret = "$f$value$b";
          break;
        case "split":
          //             {
          //               "action": "split",
          //               "pattern": "cid=",
          //               "index": 1
          //             },
          try {
            if (ac["index"] is int) {
              ret = value
                  ?.split(exchgValue(ac["pattern"]) ?? "")
                  .elementAt(ac["index"] ?? 0);
            } else if (ac["index"] is String) {
              switch (ac["index"]) {
                case "first":
                  ret = value?.split(exchgValue(ac["pattern"]) ?? "").first;
                  break;
                case "last":
                  ret = value?.split(exchgValue(ac["pattern"]) ?? "").last;
                  break;
                default:
                  ret = value;
                  break;
              }
            }
          } catch (e) {
            ret = "";
          }
          break;
        case "trim":
          //            {
          //              "action": "trim"
          //            }
          ret = value?.trim();
          break;
        case "setValue":
          //            {
          //              "action": "setValue",
          //              "valueName": "pageUrl",
          //              "value":"http://www.163.com", //*
          //              "valueProcess":[] //*
          //            }
          //            如果value及valueProcess均为null则设 action value 为存入值
          if (ac["valueName"] != null) {
            setValue(
                ac["valueName"],
                exchgValue(ac["value"]) ??
                    await singleProcess(value, ac["valueProcess"] ?? []));
          }
          refreshValue = false;
          break;
        case "getValue":
          //            {
          //              "action": "getValue",
          //              "value": "url",   //*
          //              "exp": "{novelName}-{writer}"   //*
          //            }
          //            value和exp两者只有其中一个生效，exp的优先级更高
          ret = exchgValue(ac["exp"]) ?? getValue(ac["value"]??"");
          break;
        case "removeValue":
          //            {
          //              "action": "removeValue",
          //              "valueName": "pageUrl"
          //            }
          if (ac["valueName"] != null) removeValue(ac["valueName"]);
          refreshValue = false;
          break;
        case "clearEnv":
          //            {
          //              "action": "clearEnv",
          //            }
          clear();
          refreshValue = false;
          break;
        case "push":
          //             {
          //               "action": "push"
          //             },
          tStack.add(value);
          refreshValue = false;
          break;
        case "pop":
          //            {
          //               "action": "pop"
          //             }
          ret = tStack.removeLast();
          break;
        case "json":
          //            {
          //               "action": "json",
          //               "keyName": "info"
          //             },
          if (ac["keyName"] != null && value != null) {
            try {
              ret = jsonDecode(value)[ac["keyName"]];
            } catch (e) {
              ret = "";
            }
          }else{
            ret = "";
          }
          break;
        case "readFile":
          //            {
          //               "action": "readFile",
          //               "fileName": "{basePath}/file1.txt",
          //               "toValue": "txtfile"
          //             },
          if (ac["fileName"] != null) {
            String fileContent = readFile(exchgValue(ac["fileName"])) ?? "";
            if (ac["toValue"] != null) {
              setValue(exchgValue(ac["toValue"])!, fileContent);
              ret = value;
            } else
              ret = fileContent;
          }
          break;
        case "saveFile":
          //            {
          //               "action": "saveFile",
          //               "fileName": "{basePath}/file1.txt",
          //               "saveContent": "{title}\n\r{content}"
          //               "mode": "append"//默认  可选"overwrite"
          //             },
          if (ac["fileName"] != null) {
            FileMode fileMode =
                ((ac["mode"] ?? "append") as String).compareTo("append") == 0
                    ? FileMode.append
                    : FileMode.write;
            saveFile(exchgValue(ac["fileName"])!,
                exchgValue(ac["saveContent"]) ?? value ?? "",
                fileMode: fileMode);
          }
          refreshValue = false;
          break;
        case "saveUrlFile":
          //            {
          //               "action": "saveUrlFile",
          //               "fileName": "{basePath}/file1.jpg",
          //               "url": "http://pic.baidu.com/sample.jpg",
          //               "overwrite": true    //* 默认为false
          //             },
          if (ac["url"] != null) {
            saveUrlFile(exchgValue(ac["url"])!,
                saveFileWithoutExt: exchgValue(ac["fileName"]),
                overwrite: ac["overwrite"] ?? false);
          }
          refreshValue = false;
          break;
        case "getHtml": //根据htmlUrl获取Html内容，转码后返回给ret
          //        {
          //           "action": "getHtml",
          //           "url": "{url}/search.html",
          //           "method": "post",
          //           "headers": {
          //             "Content-Type": "application/x-www-form-urlencoded"
          //           },
          //           "body": "searchtype=all&searchkey={searchkey}",
          //           "charset": "utf8"
          //         }
          //        {
          //           "action": "getHtml",
          //           "url": "{url}/modules/article/search.php",
          //           "queryParameters": {
          //              "searchtype": "articlename",
          //              "searchkey": "{searchkey}"
          //           },
          //           "method": "get",
          //           "charset": "gbk"
          //         }
          String? htmlUrl = exchgValue(ac["url"]) ?? value;
          if (htmlUrl != null) {
            // logger.fine("htmlUrl=$htmlUrl");
            String? body = exchgValue(ac["body"]);

            Encoding encoding =
                "gbk".compareTo(ac["charset"]) == 0 ? gbk : utf8;

            // Map<String, dynamic> queryParameters =
            //     Map.castFrom(ac["queryParameters"] ?? {});
            // queryParameters.forEach((key, value) async {
            //   if (value is String) {
            //     queryParameters[key] = Uri.encodeQueryComponent(
            //         exchgValue(value)!,
            //         encoding: encoding);
            //   }
            // });
            Map<String, dynamic> queryParameters = {};
            var scriptQueryParameters = ac["queryParameters"] ?? {};
            if (scriptQueryParameters is Map) {
              scriptQueryParameters.forEach((key, value) {
                queryParameters[key] = value is String
                    ? Uri.encodeQueryComponent(exchgValue(value)!,
                        encoding: encoding)
                    : value;
              });
            }

            Map<String, dynamic> headers = Map.castFrom(ac["headers"] ?? {});

            RequestMethod method = "post".compareTo(ac["method"] ?? "get") == 0
                ? RequestMethod.post
                : RequestMethod.get;

            ret = await getHtml(htmlUrl,
                method: method,
                encoding: encoding,
                headers: headers,
                body: body,
                queryParameters: queryParameters,
                debugId: debugId,
                debugMode:
                    debugMode && Logger.root.level.value > Level.FINE.value);
          } else {
            logger.warning("url is null");
          }
          break;
        case "htmlDecode":
          //           {
          //             "action": "htmlDecode"
          //           }
          ret = HtmlCodec().decode(value);
          break;
        case "selector":
          switch (ac["type"]) {
            //            {
            //               "action": "selector",
            //               "type": "dom",
            //               "script": "[property=\"og:novel:book_name\"]",
            //               "property": "content"
            //             }
            case "dom":
              var tmp = HtmlParser(value)
                  .parse()
                  .querySelector(exchgValue(ac["script"]) ?? "");
              if (tmp != null) {
                switch (ac["property"] ?? "innerHtml") {
                  case "innerHtml":
                    ret = tmp.innerHtml;
                    break;
                  case "outerHtml":
                    ret = tmp.outerHtml;
                    break;
                  case "content":
                    ret = tmp.attributes["content"];
                    break;
                  default:
                    ret = tmp.attributes[ac["property"]] ?? "";
                }
              } else
                ret = "";
              break;
            //            {
            //               "action": "selector",
            //               "type": "xpath",
            //               "script": "//p[3]/span[1]/text()"
            //             },
            case "xpath":
              ret = XPath.source(value ?? "").query(ac["script"] ?? "").get();
              break;
            //            {
            //               "action": "selector",
            //               "type": "regexp",
            //               "script": "<[^>]*>"
            //             }, //仅匹配第一次发现的
            case "regexp":
              RegExpMatch? rem = RegExp(exchgValue(ac["script"]) ?? "")
                  .firstMatch(value ?? "");
              if (rem != null) {
                if (rem.groupCount > 0)
                  ret = rem.group(1);
                else
                  ret = rem.group(0);
              }
              break;
          }
          break;
        case "selectorAt":
          //          {
          //             "action": "selectorAt",
          //             "type": "dom",
          //             "script": "div.book_list",
          //             "index": 1
          //           }
          switch (ac["type"]) {
            case "dom":
              var tmps =
                  HtmlParser(value).parse().querySelectorAll(ac["script"]);
              var tmp;
              if ((tmps.length) > 0) tmp = tmps.elementAt(ac["index"] ?? 0);
              if (tmp != null) {
                switch (ac["property"] ?? "innerHtml") {
                  case "innerHtml":
                    ret = tmp.innerHtml;
                    break;
                  case "outerHtml":
                    ret = tmp.outerHtml;
                    break;
                  case "content":
                    ret = tmp.attributes["content"];
                    break;
                  default:
                    ret = tmp.attributes[ac["property"]] ?? "";
                }
              } else
                ret = "";
              break;
            case "xpath":
              var tmps =
                  XPath.source(value ?? "").query(ac["script"] ?? "").list();
              if (tmps.length > 0)
                ret = tmps.elementAt(ac["index"] ?? 0);
              else
                ret = "";
              break;
            case "regexp":
              RegExpMatch? rem = RegExp(exchgValue(ac["script"]) ?? "")
                  .firstMatch(value ?? "");
              if (rem != null) {
                if (rem.groupCount > 0)
                  ret = rem.group(ac["index"] ?? 0);
                else
                  ret = rem.group(0);
              }
              break;
          }
          break;
        case "for":
          // {
          //   "action": "for",
          //   "valueName": "ipage",
          //   "type": "list",
          //   "range": [1,10],     // as String "1-10"
          //   "list": [1,2,4,5,7], // as String "1,2,3,4"
          //   "loopProcess": []
          // }
          var loopCfg = ac["loopProcess"];
          List<String> retList = [];
          if (loopCfg != null && (ac["list"] != null || ac["range"] != null)) {
            switch (ac["type"]) {
              case "list":
                if (ac["list"] != null) {
                  var listVar = ac["list"];
                  if (listVar is String) {
                    for (String i in exchgValue(listVar)!.split(",")) {
                      setValue(ac["valueName"], i);
                      retList.add(await singleProcess(value, loopCfg) ?? "");
                    }
                  }
                  if (listVar is List) {
                    for (int i in listVar) {
                      setValue(ac["valueName"], i.toString());
                      retList.add(await singleProcess(value, loopCfg) ?? "");
                    }
                  }
                }
                break;
              case "range":
                if (ac["range"] != null) {
                  var rangeVar = ac["range"];
                  if (rangeVar is List) {
                    for (int i = rangeVar[0]; i < rangeVar[1]; i++) {
                      setValue(ac["valueName"], i.toString());
                      retList.add(await singleProcess(value, loopCfg) ?? "");
                    }
                  }
                  if (rangeVar is String) {
                    for (int i =
                            int.tryParse(exchgValue(rangeVar)!.split("-")[0]) ??
                                1;
                        i <
                            (int.tryParse(
                                    exchgValue(rangeVar)!.split("-")[1]) ??
                                1);
                        i++) {
                      setValue(ac["valueName"], i.toString());
                      retList.add(await singleProcess(value, loopCfg) ?? "");
                    }
                  }
                }
                break;
            }
          }
          ret = retList.toString();
          break;

        ///条件分支执行
        case "condition":
          //     {
          //       "action": "condition",
          //       "exps": [{
          //         "expType": "contain",
          //         "exp": "搜索结果",
          //         "source":"{title}"     //source.contain(exp)
          //       }],
          //       "trueProcess": [],
          //       "falseProcess": []
          //     }
          if (conditionPatch(value, ac["condExps"], debugId: debugId)) {
            ret = await singleProcess(value, ac["trueProcess"]??[]);
          } else {
            ret = await singleProcess(value, ac["falseProcess"]??[]);
          }
          break;

        case "callMultiProcess":
          //    {
          //       "action": "callMultiProcess",
          //       "multiBuilder":[
          //        {
          //          "action": "fill",
          //          "valueName": "ipage",
          //          "type": "list",
          //          "range": [1,10],     // as String "1-10"
          //          "list": [1,2,4,5,7], // as String "1,2,3,4"
          //          "exp": "{url}_{ipage}"
          //        }
          //       ],
          //       "values": [],
          //       "multiProcess": []
          //    }
          var buildValues;
          if(ac["multiBuilder"]!=null){
            buildValues=await multiProcess([], ac["multiBuilder"]);
          }
          var multiResult =
              (await multiProcess(buildValues??(exchgValue(ac["values"])??[value ?? ""]), ac["multiProcess"]));
          setValue(MULTIRESULT, multiResult);
          ret = multiResult.toString();
          break;

        case "callFunction":
          // {
          //   "action": "callFunction",
          //   "functionName": "getPage",
          //   "parameters": {
          //     "page": "{ipage}"
          //   }
          // }
          if (functions[ac["functionName"]] != null) {
            if (ac["parameters"] != null && ac["parameters"] is Map) {
              Map<String, dynamic> params = Map.castFrom(ac["parameters"]);
              params.forEach((key, value) {
                setValue(key, exchgValue(value));
              });
            }
            ret = await singleProcess(
                value, functions[ac["functionName"]]["process"]);
          } else {
            logger.warning("Function ${ac["functionName"]} is not found"); //
          }
          break;

        case "exit":
          exit(ac["code"] ?? 0);
          break;

        case "break":
          setValue(RETURNCODE, 0);
          ret = null;
          break;

        default:
          if (extendSingleAction != null) {
            ret = await extendSingleAction!(value, ac,
                debugId: debugId, debugMode: debugMode);
          } else if (debugMode)
            logger.fine("Unknow config : [${ac.toString()}]");
          break;
      }
    } catch (e) {
      logger.warning(e.toString());
      logger.warning("--$debugId--💃action($ac,$value)");
      // throw e;
    }

    if (onAction != null) onAction!(value, ac, ret, debugId,this);

    if (debugMode && ret != null)
      logger.fine("--$debugId--⚠️️result[${shortString(ret)}]");
    // if (debugMode) logger.finest("--$debugId--⚠️️result[$ret]");

    if (!refreshValue) ret = value;

    return ret;
  }

  Future<List<String?>> multiProcess(
      List<String?> objs, dynamic procCfg) async {
    String debugId = genKey(lenght: 8);
    if (procCfg != null) {
      for (var act in procCfg) {
        if (isExit) break;
        List<String?> preErrorProc = objs;
        setValue("thisObjs", objs);
        objs = await mAction(objs, act, debugId: debugId);
        // if (objs == null) {
        //   logger.warning(
        //       "--$debugId--[Return null,Abort this MultiProcess! Please check multiAction($act,$preErrorProc)");
        //   break;
        // }
      }
      setValue(MULTIRESULT, objs);
    }
    return objs;
  }

  Future<List<String?>> mAction(List<String?> value, dynamic ac,
      {String debugId = ""}) async {
    List<String?> ret = [];
    if (debugMode)
      logger.fine(
          "--$debugId--🎾multiAction($ac,${shortString(value.toString())})");
    if (debugMode) logger.finest("--$debugId--value : $value)");

    switch (ac["action"]) {
      case "pause":
        if(onPause!=null) {
          state = ScriptEngineState.Pause;
          onPause!(value, ac, ret, debugId,this);
          while(state==ScriptEngineState.Pause){
            sleep(Duration(seconds: 1));
          }
        }

        ret = value;
        break;
      case "fill":
      // {
      // "action": "fill",
      // "type": "range",
      // "valueName": "ipage",
      // "range": "{pageRange}",
      // "exp": "{muluPageUrl}_{ipage}/"
      // }
        List<String> retList = [];
        if (ac["type"] != null) {
          switch (ac["type"]) {
            case "list":
              if (ac["list"] != null) {
                var listVar = ac["list"];
                if (listVar is String) {
                  for (String i in exchgValue(listVar)!.split(",")) {
                    setValue(ac["valueName"], i);
                    if (exchgValue(ac["exp"]) != null) retList.add(
                        exchgValue(ac["exp"])!);
                  }
                }
                if (listVar is List) {
                  for (int i in listVar) {
                    setValue(ac["valueName"], i.toString());
                    if (exchgValue(ac["exp"]) != null) retList.add(
                        exchgValue(ac["exp"])!);
                  }
                }
              }
              break;
            case "range":
              if (ac["range"] != null) {
                var rangeVar = ac["range"];
                if (rangeVar is List) {
                  for (int i = rangeVar[0]; i <= rangeVar[1]; i++) {
                    setValue(ac["valueName"], i.toString());
                    if (exchgValue(ac["exp"]) != null) retList.add(
                        exchgValue(ac["exp"])!);
                  }
                }
                if (rangeVar is String) {
                  for (int i =
                      int.tryParse(exchgValue(rangeVar)!.split("-")[0]) ??
                          1;
                  i <=
                      (int.tryParse(
                          exchgValue(rangeVar)!.split("-")[1]) ??
                          1);
                  i++) {
                    setValue(ac["valueName"], i.toString());
                    if (exchgValue(ac["exp"]) != null) retList.add(
                        exchgValue(ac["exp"])!);
                  }
                }
              }
              break;
          }
        }
        ret = retList;
        break;
      case "multiSelector":
        switch (ac["type"]) {
          case "fill":
          // {
            // "action": "multiSelector",
            // "type": "fill",
            // "valueName": "ipage",
            // "fillType": "range",
            // "range": "{pageRange}",
            // "exp": "{muluPageUrl}_{ipage}/"
          // }
            List<String> retList = [];
            if (ac["fillType"] != null) {
              switch (ac["fillType"]) {
                case "list":
                  if (ac["list"] != null) {
                    var listVar = ac["list"];
                    if (listVar is String) {
                      for (String i in exchgValue(listVar)!.split(",")) {
                        setValue(ac["valueName"], i);
                        if (exchgValue(ac["exp"]) != null) retList.add(
                            exchgValue(ac["exp"])!);
                      }
                    }
                    if (listVar is List) {
                      for (int i in listVar) {
                        setValue(ac["valueName"], i.toString());
                        if (exchgValue(ac["exp"]) != null) retList.add(
                            exchgValue(ac["exp"])!);
                      }
                    }
                  }
                  break;
                case "range":
                  if (ac["range"] != null) {
                    var rangeVar = ac["range"];
                    if (rangeVar is List) {
                      for (int i = rangeVar[0]; i <= rangeVar[1]; i++) {
                        setValue(ac["valueName"], i.toString());
                        if (exchgValue(ac["exp"]) != null) retList.add(
                            exchgValue(ac["exp"])!);
                      }
                    }
                    if (rangeVar is String) {
                      for (int i =
                          int.tryParse(exchgValue(rangeVar)!.split("-")[0]) ??
                              1;
                      i <=
                          (int.tryParse(
                              exchgValue(rangeVar)!.split("-")[1]) ??
                              1);
                      i++) {
                        setValue(ac["valueName"], i.toString());
                        if (exchgValue(ac["exp"]) != null) retList.add(
                            exchgValue(ac["exp"])!);
                      }
                    }
                  }
                  break;
                }
              }
            ret = retList;
            break;
          case "dom":
            //            {
            //               "action": "multiSelector",
            //               "type": "dom",
            //               "script": ".sbintro",
            //               "property": "innerHtml"
            //             }
            var tmp=HtmlParser(value[0] ?? "")
                .parse()
                .querySelectorAll(ac["script"]);

            ret = [];
            for (Element e in tmp) {
              switch (ac["property"] ?? "innerHtml") {
                case "innerHtml":
                  ret.add(e.innerHtml);
                  break;
                case "outerHtml":
                  ret.add(e.outerHtml);
                  break;
                case "content":
                  ret.add(e.attributes["content"]);
                  break;
                default:
                  ret.add(e.attributes[ac["property"]] ?? "");
              }
            }
            break;
          case "xpath":
            //          {
            //             "action": "multiSelector",
            //             "type": "xpath",
            //             "script": "//a/@href"
            //           }
            ret = XPath.source(value[0] ?? "").query(ac["script"]).list();
            break;
            //            {
            //               "action": "multiSelector",
            //               "type": "regexp",
            //               "script": "<[^>]*>"
            //             }, //匹配所有发现的
          case "regexp":
            Iterable<RegExpMatch> rem = RegExp(exchgValue(ac["script"]) ?? "")
                .allMatches(value[0] ?? "");
            ret = [];
            for (RegExpMatch m in rem) {
              if (m.groupCount > 0)
                ret.add(m.group(1));
              else
                ret.add(m.group(0));
            }
            break;
        }
        break;
      case "remove":
        //          {
        //             "action": "remove",
        //             "index": 0,    //*
        //             "except": 2    //*
        //             "condition": []    //*
        //           }
        //          index优先级更高,except次之,condition最低
        var index = ac["index"];
        if (index != null) {
          if (index is int) value.removeAt(index);
          if (index is String) {
            if ("first".compareTo(index.toLowerCase()) == 0) value.removeAt(0);
            if ("last".compareTo(index.toLowerCase()) == 0) value.removeLast();
          }
        } else if (ac["except"] != null && ac["except"] is int) {
          value = [value.removeAt(ac["except"])];
        } else if (ac["condExps"] != null) {
          value.removeWhere(
              (element) => conditionPatch(element, ac["condExps"]));
        }
        ret = value;
        break;
      case "sort":
        //            {
        //               "action": "sort",
        //               "asc": true
        //             },
        if (ac["asc"] ?? true) {
          value.sort((l, r) => (l ?? "").compareTo(r ?? ""));
        } else {
          value.sort((l, r) => (r ?? "").compareTo(l ?? ""));
        }
        ret = value;
        break;
      case "sublist":
        //          {
        //             "action": "sublist",
        //             "begin": 12
        //           }
        //          {
        //             "action": "sublist",
        //             "begin": 12,
        //             "end": 20
        //           }
        if (ac["end"] != null) {
          ret = value.sublist(ac["begin"] ?? 0, ac["end"]);
        } else {
          ret = value.sublist(ac["begin"] ?? 0);
        }
        break;
      case "saveMultiToFile":
        //            {
        //               "action": "saveMultiToFile",
        //               "fileName": "{basePath}/file1.txt"
        //             },
        File saveFile;
        if (ac["fileName"] != null) {
          saveFile = File(exchgValue(ac["fileName"])!);
          if (!saveFile.existsSync()) saveFile.createSync(recursive: true);
          for (String? line in value) {
            saveFile.writeAsStringSync(line ?? "",
                mode: FileMode.append, encoding: utf8, flush: true);
          }
          ret = value;
        }
        break;
      case "foreach":
        // {
        //   "action": "foreach",
        //   "eachProcess": [
        //     {
        //     "action": "print",
        //     "value": "正在下载{this}"
        //     },
        //     {
        //     "action": "callFunction",
        //     "functionName": "downloadPic"
        //     }
        //   ]
        // }
        List<String?> tmpList = [];

        for (String? one in value) {
          ///如果单条处理存在则先处理
          if ((ac["eachProcess"]?.length ?? 0) > 0)
            tmpList.add(await singleProcess(one, ac["eachProcess"]));

          // /如果分离操作存在则在这里执行处理，否则将单条处理结果加入返回列表
          // if ((actCfg["splitProcess"] ?? []).length > 0) {
          //   tmpList.addAll(await multiProcess([one], actCfg["splitProcess"]));
          // } else {
          //   tmpList.add(one);
          // }
        }
        ret = tmpList;
        break;
      case "foreach2":
        //        {
        //           "action": "foreach2",    //旧版本兼容
        //           "preProcess": [
        //             {
        //               "action": "selector",
        //               "type": "dom",
        //               "script": ".xs-list"
        //             }
        //           ],
        //           "splitProcess": [
        //             {
        //               "action": "multiSelector",
        //               "type": "xpath",
        //               "script": "//ul/li"
        //             }
        //           ]
        //         }
        List<String?> tmpList = [];

        for (String? one in value) {
          ///如果单条处理存在则先处理
          if ((ac["preProcess"] ?? []).length > 0)
            one = await singleProcess(one, ac["preProcess"]);

          ///如果分离操作存在则在这里执行处理，否则将单条处理结果加入返回列表
          if ((ac["splitProcess"] ?? []).length > 0) {
            tmpList.addAll(await multiProcess([one], ac["splitProcess"]));
          } else {
            tmpList.add(one);
          }
        }

        ret = tmpList;
        break;
      default:
        if (extendSingleAction != null) {
          ret = await extendMultiAction!(value, ac,
              debugId: debugId, debugMode: debugMode);
        } else if (debugMode)
          logger.warning("Unknow config : [${ac.toString()}]");
        break;
    }

    if (onAction != null) onAction!(value, ac, ret, debugId,this);

    if (debugMode)
      logger.fine("--$debugId--🧩result[${shortString(ret.toString())}]");
    // if (debugMode) logger.finest("--${debugId ?? ""}--🧩result[$ret]");
    return ret;
  }

  bool conditionPatch(String? value, dynamic condCfg, {String? debugId}) {
    bool? result;
    if (condCfg != null) {
      for (var cond in condCfg) {
        result = condition(value, cond, patchResult: result, debugId: debugId);
      }
    }
    return result ?? false;
  }

  bool? condition(String? value, dynamic ce,
      {bool? patchResult, String? debugId}) {
    String? condValue = exchgValue(ce["source"]) ?? value;
    var exp = ce["exp"];
    if (exp is String) {
      exp = exchgValue(exp);
    } else if (exp is List) {
      for (int i = 0; i < exp.length; i++) {
        exp[i] = exchgValue(exp[i]);
      }
    }

    switch (ce["expType"]) {
      case "isNull":
        patchResult =
            relationAction(patchResult, condValue == null, ce["relation"]);
        break;
      case "isEmpty":
        patchResult = relationAction(
            patchResult, condValue?.isEmpty ?? true, ce["relation"]);
        break;
      case "in":
        // {
        //       "expType": "in",
        //       "exp": "jpg,png,jpeg,gif,bmp",
        //       "not": true
        // }
        patchResult = relationAction(
            patchResult, (exp as String).split(",").contains(condValue), ce["relation"]);
        break;
      case "compare":
        // {
        //       "expType": "compare",
        //       "exp": "viewthread.php",
        //       "source": "{system.platform}", //* 存在则优先处理
        //       "not": true
        // }
        patchResult = relationAction(
            patchResult,
            notAction(ce["not"], condValue?.compareTo(exp) == 0),
            ce["relation"]);
        break;
      case "contain":
        // {
        //       "expType": "contain",
        //       "exp": "viewthread.php",   //  exp: [jpg, gif, bmp, png, jpeg],
        //       "source": "{system.platform}", //* 存在则优先处理
        //       "relation": "and"
        // }
        if (exp is String) {
          patchResult = relationAction(
              patchResult,
              notAction(ce["not"], condValue?.contains(exp) ?? false),
              ce["relation"]);
        } else if (exp is List) {
          bool listResult = false;
          exp.forEach((element) {
            listResult = (condValue?.contains(element) ?? false) || listResult;
          });
          patchResult = relationAction(
              patchResult, notAction(ce["not"], listResult), ce["relation"]);
        }
        break;
      case "not": //如果patchResult
        // patchResult = relationAction(patchResult, value.contains(exp),condExp["relation"]);
        patchResult = !(patchResult ?? false);
        break;
      default:
        break;
    }
    if (debugMode)
      logger.fine(
          "--${debugId ?? ""}--⚖️condition($ce,$condValue)--🔐result[$patchResult]");
    return patchResult;
  }

  bool notAction(bool? isNot, bool value) {
    return isNot ?? false ? !value : value;
  }

  bool relationAction(bool? origin, bool value, String? relation) {
    bool result;
    result = origin ?? value;
    if (relation != null) {
      switch (relation) {
        case "and":
          result = result && value;
          break;
        case "or":
          result = result || value;
          break;
        // case "not":
        //   result = !result;
        //   break;
        default:
          break;
      }
    }
    return result;
  }
}
