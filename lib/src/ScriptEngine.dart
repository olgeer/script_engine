import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart';
import 'package:html/dom.dart';
import 'package:base_utility/console_utility.dart';
import 'package:xpath_parse/xpath_selector.dart';
import 'cmdDefine.dart';
import 'HtmlCodec.dart';

typedef SingleAction = Future<String?> Function(String? value, Map<String, dynamic> ac,ScriptEngine se,
    String? debugId, bool? debugMode);
typedef MultiAction = Future<List<String?>> Function(
    List<String?> value, Map<String, dynamic> ac,ScriptEngine se,
    String? debugId, bool? debugMode);
typedef ValueProvider = String Function(String exp);
typedef ActionEvent = Future<void> Function(
    dynamic value, Map<String, dynamic> ac, ScriptEngine se, dynamic ret, String debugId);
enum ScriptEngineState { Initing, Ready, Running, Done, Pause }

class ScriptEngine {
  Map<String, dynamic> _values = {}; //配置运行时临时变量表
  List<String?> _stacks = []; //配置运行时堆栈
  Map<String, dynamic> globalValue={};
  Map<String, dynamic> functions = {};
  bool debugMode;

  late dynamic scriptSource;
  String? script;
  late Map<String, dynamic> scriptJson;
  late String mainProcess;

  SingleAction? extendSingleAction;
  MultiAction? extendMultiAction;
  ValueProvider? extendValueProvide;

  ActionEvent? beforeAction, afterAction;
  ActionEvent? onPause;
  void Function(ScriptEngineState s)? onScriptEngineStateChange;

  final Logger logger = Logger("ScriptEngine");

  final String MULTIRESULT = "multiResult";
  final String SINGLERESULT = "singleResult";
  final String RETURNCODE = "returnCode";
  bool isExit = false;
  ScriptEngineState _state=ScriptEngineState.Initing;

  set state(ScriptEngineState s){
    this._state=s;
    if(onScriptEngineStateChange!=null)onScriptEngineStateChange!(s);
  }

  ///初始化json脚本引擎，暂时一个脚本对应一个引擎，拥有独立的变量及堆栈空间
  ///scriptSource可以是String，Uri，File等类型，指向json脚本内容
  ScriptEngine(
      {this.scriptSource,
      this.extendSingleAction,
      this.extendMultiAction,
      this.extendValueProvide,
      this.beforeAction,
      this.afterAction,
      this.onPause,
      this.onScriptEngineStateChange,
      this.debugMode = false});

  Future<ScriptEngine> init() async {
    await initScript(scriptSource);
    return this;
  }

  static Future<String?> loadScript(dynamic scriptSrc) async {
    String? s;
    if (scriptSrc is Uri) {
      if (scriptSrc.isScheme("file")) s = read4File(File(scriptSrc.path));
      if (scriptSrc.isScheme("https") || scriptSrc.isScheme("http"))
        s = await getHtml(scriptSrc.toString());
    }
    if (scriptSrc is File) {
      s = read4File(scriptSrc);
    }
    if (scriptSrc is String) {
      if (scriptSrc.startsWith("http")) {
        s = await getHtml(scriptSrc);
      } else if (scriptSrc.startsWith("file")) {
        s = read4File(File(Uri.parse(scriptSrc).path));
      } else {
        s = scriptSrc;
      }
    }
    return s;
  }

  Future<void> initScript(dynamic scriptSrc) async {
    if (_state == ScriptEngineState.Initing) {
      state=ScriptEngineState.Initing;

      try {
        script = await loadScript(scriptSrc);
        scriptJson = cmdLowcase(json.decode(script ?? "{}"));
      } catch (e) {
        print(e);
        scriptJson = {};
      }

      // 原格式逻辑
      // mainProcess = scriptJson.v(C_PROCESS_NAME) ?? "MainProcess";
      // if (scriptJson.v(C_VALUE_DEFINE) != null) {
      //   globalValue = Map.castFrom(scriptJson.v(C_VALUE_DEFINE) ?? {});
      //   reloadGlobalValue();
      // }
      // functions = Map.castFrom(scriptJson.v(C_FUNCTION_DEFINE) ?? {});

      mainProcess = initFunction(scriptJson);
      reloadGlobalValue();

      state = ScriptEngineState.Ready;
      logger.fine("Script Engine init success !");
    } else {
      logger.fine("Script Engine had inited !");
    }
  }

  String initFunction(Map<String, dynamic> functionJson){
    ///获取方法名
    String processName=functionJson.v(C_PROCESS_NAME);

    ///添加到functions
    functions.putIfAbsent(processName, () => functionJson.v(C_PROCESS));

    ///添加全局变量
    if (functionJson.v(C_VALUE_DEFINE) != null) {
      Map.castFrom(functionJson.v(C_VALUE_DEFINE) ?? {}).forEach((key, value) {
        globalValue.putIfAbsent(key, () => value);
      });
    }

    ///递归添加子方法
    if(functionJson.v(C_FUNCTION_DEFINE)!=null){
      List.castFrom(functionJson.v(C_FUNCTION_DEFINE) ?? []).forEach((element) {
        if(element is Map<String, dynamic>){
          initFunction(cmdLowcase(element));
        }
      });
    }

    return processName;
  }

  ///直接执行脚本，所有处理均包含在脚本内，对最终结果不太关注
  Future<String?> run({bool stepByStep = false}) async {
    if (_state != ScriptEngineState.Ready) await init();

    // if (scriptJson.v(C_PROCESS) != null) {
    if(functions[mainProcess]!=null){
      state = ScriptEngineState.Running;

      String? ret = await singleProcess("", functions[mainProcess]);

      state = ScriptEngineState.Done;
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
    _values.clear();
    _stacks.clear();
    reloadGlobalValue();
  }

  void reloadGlobalValue() {
    globalValue.forEach((key, value) {
      setValue(key, value);
    });
  }

  String? exchgValue(String? exp,{Encoding? encoding}) {
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
              repValue = encoding==null?v:Uri.encodeQueryComponent(v,encoding: encoding);
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
    _values[key] = value;
    // } else {
    //   tValue.putIfAbsent(key, () => value);
    // }
    if (debugMode) logger.finer("Set value($key) to $value");
  }

  String removeValue(String key) => _values.remove(key);

  dynamic getValue(String key) => _values[key];

  Future<String?> singleProcess(String? value, List? procCfg) async {
    if (procCfg != null) {
      String debugId = genKey(lenght: 8);

      for (var act in procCfg) {
        if (isExit) break;
        String? preErrorProc = value;
        setValue("this", value);

        Map<String, dynamic> newAct = cmdLowcase(act);
        // logger.fine(newAct.toString());

        value = await action(value, newAct, debugId: debugId);
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

  Future<String?> action(String? value, Map<String,dynamic> ac,
      {String debugId = ""}) async {
    String? ret;
    bool refreshValue = true;

    if (beforeAction != null) {
      await beforeAction!(value, ac, this, ret, debugId);
    }

    if (debugMode) logger.fine("--$debugId--💃action($ac)");
    if (debugMode) logger.finest("--$debugId--value : $value");

    try {
      switch (strLowcase(ac.v(C_ACT,whenNull:"unknown"))) {
        case "pause":
          if (onPause != null) {
            state = ScriptEngineState.Pause;
            await onPause!(value, ac, this, ret, debugId);
            // while (_state == ScriptEngineState.Pause) {
            //   sleep(Duration(seconds: 1));
            // }
            state = ScriptEngineState.Running;
          }

          refreshValue = false;
          break;
        case "print":
          //           {
          //             "action": "print",
          //             "value": "url"   //*
          //           }
          // logger.info(exchgValue(ac["value"]) ?? value);
          largeLog(exchgValue(ac.v(C_VALUE)) ?? value,
              logHandle: logger, level: Level.INFO);

          refreshValue = false;
          break;
        case "replace":
          //             {
          //               "action": "replace",
          //               "from": "<(\\S+)[\\S| |\\n|\\r]*?>[^<]*</\\1>",
          //               "to": ""
          //             },
          if (ac.v(C_FROM) != null) {
            ret = value?.replaceAll(
                RegExp(exchgValue(ac.v(C_FROM))!), exchgValue(ac.v(C_TO)) ?? "");
          } else {
            ret = value;
          }
          break;
        case "substring":
          //             {
          //               "action": "substring",
          //               "start": 2,  // 为null 则 从0开始，如果为 负数 则从后面算起，如 "abcde" ,-2则指从'd'起
          //               "end": 10,   // 为null 则 到结尾，当end值小于begin值时，两值对调，如为负数则从开始算起
          //               "length": 4  // 当end为null时，解释此参数，如亦为null则忽略此逻辑
          //             },
          if (value != null) {
            int start = ac.v(C_START) ?? 0;
            int? end = ac.v(C_END);
            int? length = ac.v(C_LENGTH);
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
          String f = ac.v(C_START) ?? "";
          String b = ac.v(C_END) ?? "";
          f = exchgValue(f)!;
          b = exchgValue(b)!;
          ret = "$f${value ?? ""}$b";
          break;
        case "split":
          //             {
          //               "action": "split",
          //               "value": "cid=43",
          //               "pattern": "cid=",
          //               "index": 1   //从0开始
          //             },
          try {
            value = exchgValue(ac.v(C_VALUE)) ?? value;
            if (value != null) {
              ///index为负数时，意味着倒数第几个，如-1为倒数第一个，即最后一个，如此类推
              if (ac.v(C_INDEX) is int) {
                List<String> splitArray =
                    value.split(exchgValue(ac.v(C_EXP)) ?? "");

                int idx = ac.v(C_INDEX) >= 0
                    ? ac.v(C_INDEX)
                    : splitArray.length + ac.v(C_INDEX);
                if (idx <= splitArray.length) {
                  ret = splitArray.elementAt(idx);
                } else {
                  logger.warning("下标越界，idx为$idx");
                }
              } else if (ac.v(C_INDEX) is String) {
                switch (strLowcase(ac.v(C_INDEX))) {
                  case "first":
                    ret = value.split(exchgValue(ac.v(C_EXP)) ?? "").first;
                    break;
                  case "last":
                    ret = value.split(exchgValue(ac.v(C_EXP)) ?? "").last;
                    break;
                  default:
                    ret = value;
                    break;
                }
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
        case "setvalue":
          //            {
          //              "action": "setValue",
          //              "valueName": "pageUrl",
          //              "value":"http://www.163.com", //*
          //              "valueProcess":[] //*
          //            }
          //            如果value及valueProcess均为null则设 action value 为存入值
          if (ac.v(C_VALUE_NAME) != null) {
            setValue(
                ac.v(C_VALUE_NAME),
                exchgValue(ac.v(C_VALUE)) ??
                    await singleProcess(value, ac.v(C_PROCESS) ?? []));
          }
          refreshValue = false;
          break;
        case "getvalue":
          //            {
          //              "action": "getValue",
          //              "value": "url",   //*
          //              "exp": "{novelName}-{writer}"   //*
          //            }
          //            value和exp两者只有其中一个生效，exp的优先级更高
          ret = exchgValue(ac.v(C_EXP)) ?? getValue(ac.v(C_VALUE) ?? "");
          break;
        case "removevalue":
          //            {
          //              "action": "removeValue",
          //              "valueName": "pageUrl"
          //            }
          if (ac.v(C_VALUE_NAME) != null) removeValue(ac.v(C_VALUE_NAME));
          refreshValue = false;
          break;
        case "clearenv":
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
          _stacks.add(value);
          refreshValue = false;
          break;
        case "pop":
          //            {
          //               "action": "pop"
          //             }
          ret = _stacks.removeLast();
          break;
        case "json":
          //            {
          //               "action": "json",
          //               "keyName": "info"
          //             },
          if (ac.v(C_VALUE_NAME) != null && value != null) {
            try {
              ret = jsonDecode(value)[ac.v(C_VALUE_NAME)];
            } catch (e) {
              ret = "";
            }
          } else {
            ret = "";
          }
          break;
        case "readfile":
          //            {
          //               "action": "readFile",
          //               "fileName": "{basePath}/file1.txt",
          //               "valueName": "txtfile"
          //             },
          if (ac.v(C_FILE_NAME) != null) {
            String fileContent = read4File(exchgValue(ac.v(C_FILE_NAME))) ?? "";
            if (ac.v(C_VALUE_NAME) != null) {
              setValue(exchgValue(ac.v(C_VALUE_NAME))!, fileContent);
              ret = value;
            } else
              ret = fileContent;
          }
          break;
        case "savefile":
          //            {
          //               "action": "saveFile",
          //               "fileName": "{basePath}/file1.txt",
          //               "value": "{title}\n\r{content}"
          //               "fileMode": "append"//默认  可选"overwrite"
          //             },
          if (ac.v(C_FILE_NAME) != null) {
            FileMode fileMode =
                (strLowcase(ac.v(C_FILE_MODE) ?? "append")).compareTo("append") ==
                        0
                    ? FileMode.append
                    : FileMode.write;
            save2File(exchgValue(ac.v(C_FILE_NAME))!,
                exchgValue(ac.v(C_VALUE)) ?? value ?? "",
                fileMode: fileMode);
          }
          refreshValue = false;
          break;
        case "saveurlfile":
          //            {
          //               "action": "saveUrlFile",
          //               "fileName": "{basePath}/file1.jpg",
          //               "url": "http://pic.baidu.com/sample.jpg",
          //               "fileMode": "overwrite"
          //             },
          if (ac.v(C_URL) != null) {
            FileMode fileMode = (strLowcase(ac.v(C_FILE_MODE) ?? "overwrite"))
                        .compareTo("append") ==
                    0
                ? FileMode.append
                : FileMode.write;
            saveUrlFile(exchgValue(ac.v(C_URL))!,
                saveFileWithoutExt: exchgValue(ac.v(C_FILE_NAME)),
                fileMode: fileMode);
          }
          refreshValue = false;
          break;
        case "gethtml": //根据htmlUrl获取Html内容，转码后返回给ret
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
          Encoding encoding = getEncoding(exchgValue(ac.v(C_CHARSET)) ?? "");
          // "utf8".compareTo(strLowcase(exchgValue(ac["charset"]) ?? "")) ==
          //     0
          //     ? utf8
          //     : gbk;
          String? htmlUrl = exchgValue(ac.v(C_URL)) ?? value;
          if (htmlUrl != null) {
            // logger.fine("htmlUrl=$htmlUrl");

            String? body = exchgValue(ac.v(C_BODY),encoding:encoding);

            Map<String, dynamic> queryParameters = {};
            var scriptQueryParameters = ac.v(C_PARAMETERS) ?? {};
            if (scriptQueryParameters is Map) {
              String query="";
              scriptQueryParameters.forEach((key, value) {
                query+="$key=";
                query+=value is String
                    ? ac.v(C_IS_ENCODE) ?? true
                    ? Uri.encodeQueryComponent(exchgValue(value)??"",
                    encoding: encoding)
                    : exchgValue(value)??""
                    : value.toString();
                // queryParameters[key] = value is String
                //     ? ac["isencode"] ?? true
                //         ? Uri.encodeQueryComponent(exchgValue(value)!,
                //             encoding: encoding)
                //         : exchgValue(value)
                //     : value;
              });
              if(query.isNotEmpty) {
                htmlUrl += (htmlUrl.contains("?") ? "&" : "?") + query;
              }
            }

            Map<String, dynamic> headers = {};
            Map.castFrom(ac.v(C_HEADERS) ?? {}).forEach((key, value) {
              headers.putIfAbsent(key, () => value is String?exchgValue(value):value);
            });

            RequestMethod method = "post".compareTo(ac.v(C_METHOD) ?? "get") == 0
                ? RequestMethod.post
                : RequestMethod.get;

            ret = await getHtml(htmlUrl,
                method: method,
                encoding: encoding,
                headers: headers,
                body: body,
                // queryParameters: queryParameters,
                debugId: debugId,
                debugMode:
                    debugMode && Logger.root.level.value <= Level.FINE.value);
          } else {
            logger.warning("url is null");
          }
          break;
        case "htmldecode":
          //           {
          //             "action": "htmlDecode"
          //           }
          if (value != null && value.isNotEmpty) {
            ret = HtmlCodec().decode(value);
          } else {
            ret = value;
          }
          break;
        case "selector":
          //          {
          //             "action": "selectorAt",
          //             "type": "dom",
          //             "script": "div.book_list",
          //             "index": 1
          //           }
          if (value != null && value.isNotEmpty) {
            switch (strLowcase(ac.v(C_TYPE))) {
              case "dom":
                var tmps = HtmlParser(value)
                    .parse()
                    .querySelectorAll(exchgValue(ac.v(C_SCRIPT)) ?? "");
                var tmp;
                if ((tmps.length) > 0) tmp = tmps.elementAt(ac.v(C_INDEX) ?? 0);
                if (tmp != null) {
                  switch (strLowcase(ac.v(C_PROPERTY) ?? "innerhtml")) {
                    case "innerhtml":
                      ret = tmp.innerHtml;
                      break;
                    case "outerhtml":
                      ret = tmp.outerHtml;
                      break;
                    case "content":
                      ret = tmp.attributes["content"];
                      break;
                    default:
                      ret = tmp.attributes[ac.v(C_PROPERTY)] ?? "";
                  }
                } else
                  ret = "";
                break;
              case "xpath":
                var tmps = XPath.source(value).query(ac.v(C_SCRIPT) ?? "").list();
                if (tmps.length > 0)
                  ret = tmps.elementAt(ac.v(C_INDEX) ?? 0);
                else
                  ret = "";
                break;
              case "regexp":
                RegExpMatch? rem =
                    RegExp(exchgValue(ac.v(C_SCRIPT)) ?? "").firstMatch(value);
                if (rem != null) {
                  if (rem.groupCount > 0)
                    ret = rem.group(ac.v(C_INDEX) ?? 0);
                  else
                    ret = rem.group(0);
                }
                break;
            }
          }
          break;
        case "for":
          // {
          //   "action": "for",
          //   "valueName": "ipage",
          //   "type": "list",
          //   "range": [1,10],     // as String "1-10"
          //   "list": [1,2,4,5,7], // as String "1,2,3,4"
          //   "process": []
          // }
          var loopCfg = ac.v(C_PROCESS);
          List<String> retList = [];
          if (loopCfg != null && (ac.v(C_LIST) != null || ac.v(C_RANGE) != null)) {
            switch (strLowcase(ac.v(C_TYPE))) {
              case "list":
                if (ac.v(C_LIST) != null) {
                  var listVar = ac.v(C_LIST);
                  if (listVar is String) {
                    for (String i in exchgValue(listVar)!.split(",")) {
                      setValue(ac.v(C_VALUE_NAME), i);
                      retList.add(await singleProcess(value, loopCfg) ?? "");
                    }
                  }
                  if (listVar is List) {
                    for (int i in listVar) {
                      setValue(ac.v(C_VALUE_NAME), i.toString());
                      retList.add(await singleProcess(value, loopCfg) ?? "");
                    }
                  }
                }
                break;
              case "range":
                if (ac.v(C_RANGE) != null) {
                  var rangeVar = ac.v(C_RANGE);
                  if (rangeVar is List) {
                    for (int i = rangeVar[0]; i < rangeVar[1]; i++) {
                      setValue(ac.v(C_VALUE_NAME), i.toString());
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
                      setValue(ac.v(C_VALUE_NAME), i.toString());
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
        case "if":
          //     {
          //       "action": "condition",
          //       "value" : "{url}",
          //       "condexps": [{
          //         "expType": "contain",
          //         "exp": "搜索结果",
          //         "source":"{title}"     //source.contain(exp)
          //       }],
          //       "trueProcess": [],
          //       "falseProcess": []
          //     }
          if (conditionPatch(ac.v(C_VALUE)??value, ac.v(C_COND_EXPS), debugId: debugId)) {
            ret = await singleProcess(ac.v(C_VALUE)??value, ac.v(C_TRUE_PROCESS) ?? []);
          } else {
            ret = await singleProcess(ac.v(C_VALUE)??value, ac.v(C_FALSE_PROCESS) ?? []);
          }
          break;

        case "callmultiprocess":
        case "runmultiprocess":
          //    {
          //       "action": "callMultiProcess",
          //       "valuesBuilder":[
          //        {
          //          "action": "fill",
          //          "valueName": "ipage",
          //          "type": "list",
          //          "range": [1,10],     // as String "1-10"
          //          "list": [1,2,4,5,7], // as String "1,2,3,4"
          //          "exp": "{url}_{ipage}"
          //        }
          //       ],
          //       "value": [],
          //       "multiProcess": []
          //    }
          var buildValues;
          if (ac.v(C_MULTI_VALUE_BUILDER) != null) {
            buildValues = await multiProcess([], ac.v(C_MULTI_VALUE_BUILDER));
          }
          var multiResult = (await multiProcess(
              buildValues ?? [exchgValue(ac.v(C_VALUE)) ?? value ?? ""],
              ac.v(C_MULTI_PROCESS)));
          // setValue(MULTIRESULT, multiResult);
          ret = multiResult.toString();
          break;

        case "callfunction":
          // {
          //   "action": "callFunction",
          //   "functionName": "getPage",
          //   "parameters": {
          //     "page": "{ipage}"
          //   }
          // }
          if (functions[ac.v(C_PROCESS_NAME)] != null) {
            if (ac.v(C_PARAMETERS) != null && ac.v(C_PARAMETERS) is Map) {
              Map<String, dynamic> params = Map.castFrom(ac.v(C_PARAMETERS));
              params.forEach((key, value) {
                setValue(key, exchgValue(value));
              });
            }
            ret = await singleProcess(
                value, functions[ac.v(C_PROCESS_NAME)]);
          } else {
            logger.warning("Function ${ac.v(C_PROCESS_NAME)} is not found");
          }
          break;

        case "break":
          setValue(RETURNCODE, 0);
          ret = null;
          break;

        case "exit":
          exit(ac.v(C_CODE) ?? 0);
        // break;

        default:
          if (extendSingleAction != null) {
            ret = await extendSingleAction!(value, ac,this,
                debugId, debugMode);
          } else if (debugMode)
            logger.fine("Unknow config : [${ac.toString()}]");
          break;
      }
    } catch (e) {
      logger.warning(e.toString());
      logger.warning("--$debugId--💃action($ac,$value)");
      // throw e;
    }

    if (afterAction != null) {
      await afterAction!(value, ac, this, ret, debugId);
    }

    if (debugMode && ret != null)
      logger.fine("--$debugId--⚠️️result[${shortString(ret)}]");
    // if (debugMode) logger.finest("--$debugId--⚠️️result[$ret]");

    if (!refreshValue) ret = value;

    return ret;
  }

  Future<List<String?>> multiProcess(
      List<String?> objs, List? procCfg) async {
    String debugId = genKey(lenght: 8);
    if (procCfg != null) {
      for (var act in procCfg) {
        if (isExit) break;
        // List<String?> preErrorProc = objs;
        setValue("thisObjs", objs);

        Map<String, dynamic> newAct = cmdLowcase(act);
        objs = await mAction(objs, newAct, debugId: debugId);
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

  Future<List<String?>> mAction(List<String?> value, Map<String, dynamic> ac,
      {String debugId = ""}) async {
    List<String?> ret = [];

    if (beforeAction != null) {
      await beforeAction!(value, ac, this, ret, debugId);
    }

    if (debugMode)
      logger.fine(
          "--$debugId--🎾multiAction($ac,${shortString(value.toString())})");
    if (debugMode) logger.finest("--$debugId--value : $value)");

    switch (strLowcase(ac.v(C_ACT))) {
      case "pause":
        if (onPause != null) {
          state = ScriptEngineState.Pause;
          await onPause!(value, ac, this, ret, debugId);
          state = ScriptEngineState.Running;
          // while (_state == ScriptEngineState.Pause) {
          //   sleep(Duration(seconds: 1));
          // }
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
        if (ac.v(C_TYPE) != null) {
          switch (strLowcase(ac.v(C_TYPE))) {
            case "list":
              if (ac.v(C_LIST) != null) {
                var listVar = ac.v(C_LIST);
                if (listVar is String) {
                  for (String i in exchgValue(listVar)!.split(",")) {
                    setValue(ac.v(C_VALUE_NAME) ?? "filltmp", i);
                    if (exchgValue(ac.v(C_EXP)) != null)
                      retList.add(exchgValue(ac.v(C_EXP))!);
                  }
                }
                if (listVar is List) {
                  for (int i in listVar) {
                    setValue(ac.v(C_VALUE_NAME) ?? "filltmp", i.toString());
                    if (exchgValue(ac.v(C_EXP)) != null)
                      retList.add(exchgValue(ac.v(C_EXP))!);
                  }
                }
              } else {
                logger.warning("Script error: Missing \"list\" part !");
              }
              break;
            case "range":
              if (ac.v(C_RANGE) != null) {
                var rangeVar = ac.v(C_RANGE);
                if (rangeVar is List) {
                  for (int i = rangeVar[0]; i <= rangeVar[1]; i++) {
                    setValue(ac.v(C_VALUE_NAME) ?? "filltmp", i.toString());
                    if (exchgValue(ac.v(C_EXP)) != null)
                      retList.add(exchgValue(ac.v(C_EXP))!);
                  }
                }
                if (rangeVar is String) {
                  for (int i =
                          int.tryParse(exchgValue(rangeVar)!.split("-")[0]) ??
                              1;
                      i <=
                          (int.tryParse(exchgValue(rangeVar)!.split("-")[1]) ??
                              1);
                      i++) {
                    setValue(ac.v(C_VALUE_NAME) ?? "filltmp", i.toString());
                    if (exchgValue(ac.v(C_EXP)) != null)
                      retList.add(exchgValue(ac.v(C_EXP))!);
                  }
                }
              } else {
                logger.warning("Script error: Missing \"range\" part !");
              }
              break;
            default:
              logger
                  .warning("Script error: Unsupport type \"\" ${ac["type"]}!");
              break;
          }
        }
        ret = retList;
        break;
      case "multiselector":
        switch (strLowcase(ac.v(C_TYPE))) {
          case "dom":
            //            {
            //               "action": "multiSelector",
            //               "type": "dom",
            //               "script": ".sbintro",
            //               "property": "innerHtml"
            //             }
            var tmp = HtmlParser(value[0] ?? "")
                .parse()
                .querySelectorAll(ac.v(C_SCRIPT));

            ret = [];
            for (Element e in tmp) {
              switch (strLowcase(ac.v(C_PROPERTY) ?? "outerhtml")) {
                case "innerhtml":
                  ret.add(e.innerHtml);
                  break;
                case "outerhtml":
                  ret.add(e.outerHtml);
                  break;
                // case "content":
                //   ret.add(e.attributes["content"]);
                //   break;
                default:
                  ret.add(e.attributes[ac.v(C_PROPERTY)] ?? "");
              }
            }
            break;
          case "xpath":
            //          {
            //             "action": "multiSelector",
            //             "type": "xpath",
            //             "script": "//a/@href"
            //           }
            ret = XPath.source(value[0] ?? "").query(ac.v(C_SCRIPT)).list();
            break;
          //            {
          //               "action": "multiSelector",
          //               "type": "regexp",
          //               "script": "<[^>]*>"
          //             }, //匹配所有发现的
          case "regexp":
            Iterable<RegExpMatch> rem = RegExp(exchgValue(ac.v(C_SCRIPT)) ?? "")
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
        //             "condExps": []    //*
        //           }
        //          index优先级更高,except次之,condition最低
        var index = ac.v(C_INDEX);
        if (index != null) {
          if (index is int) value.removeAt(index);
          if (index is String) {
            if ("first".compareTo(index.toLowerCase()) == 0) value.removeAt(0);
            if ("last".compareTo(index.toLowerCase()) == 0) value.removeLast();
          }
        } else if (ac.v(C_EXCEPT) != null && ac.v(C_EXCEPT) is int) {
          value = [value.removeAt(ac.v(C_EXCEPT))];
        } else if (ac.v(C_COND_EXPS) != null) {
          value.removeWhere(
              (element) => conditionPatch(element, ac.v(C_COND_EXPS)));
        }
        ret = value;
        break;
      case "sort":
        //            {
        //               "action": "sort",
        //               "isAsc": true
        //             },
        if (ac.v(C_IS_ASC) ?? true) {
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
        if (ac.v(C_END) != null && ac.v(C_END) is int) {
          ret = value.sublist(ac.v(C_START) ?? 0, ac.v(C_END));
        } else {
          ret = value.sublist(ac.v(C_START) ?? 0);
        }
        break;
      case "savemultitofile":
        //            {
        //               "action": "saveMultiToFile",
        //               "fileName": "{basePath}/file1.txt,
        //               "fileMode": "append" //overwrite
        //               "encoding": "utf8"   //gbk
        //             },
        File saveFile;
        FileMode fileMode = "append".compareTo(
                    strLowcase(exchgValue(ac.v(C_FILE_MODE)) ?? "append")) ==
                0
            ? FileMode.append
            : FileMode.write;
        Encoding encoding = getEncoding(exchgValue(ac.v(C_CHARSET)) ?? "");

        if (ac.v(C_FILE_NAME) != null) {
          saveFile = File(exchgValue(ac.v(C_FILE_NAME))!);
          if (!saveFile.existsSync()) saveFile.createSync(recursive: true);
          for (String? line in value) {
            saveFile.writeAsStringSync(line ?? "",
                mode: fileMode, encoding: encoding, flush: true);
          }
          ret = value;
        }
        break;
      case "foreach":
        // {
        //   "action": "foreach",
        //   "Process": [
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
          if ((ac.v(C_PROCESS)?.length ?? 0) > 0)
            tmpList.add(await singleProcess(one, ac.v(C_PROCESS)));

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
      case "foreach2step":
        //        {
        //           "action": "foreach2step",    //旧版本兼容
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
          if ((ac.v(C_PRE_PROCESS) ?? []).length > 0)
            one = await singleProcess(one, ac.v(C_PRE_PROCESS));

          ///如果分离操作存在则在这里执行处理，否则将单条处理结果加入返回列表
          if ((ac.v(C_MULTI_PROCESS) ?? []).length > 0) {
            tmpList.addAll(await multiProcess([one], ac.v(C_MULTI_PROCESS)));
          } else {
            tmpList.add(one);
          }
        }

        ret = tmpList;
        break;
      default:
        if (extendSingleAction != null) {
          ret = await extendMultiAction!(value, ac,this,
              debugId, debugMode);
        } else if (debugMode)
          logger.warning("Unknow config : [${ac.toString()}]");
        break;
    }

    if (afterAction != null) {
      await afterAction!(value, ac, this, ret, debugId);
    }

    if (debugMode)
      logger.fine("--$debugId--🧩result[${shortString(ret.toString())}]");
    // if (debugMode) logger.finest("--${debugId ?? ""}--🧩result[$ret]");
    return ret;
  }

  bool conditionPatch(String? value, List? condCfg, {String? debugId}) {
    bool? result;
    if (condCfg != null) {
      for (var cond in condCfg) {
        Map<String, dynamic> newCond = cmdLowcase(cond);
        result = condition(value, newCond, patchResult: result, debugId: debugId);
      }
    }
    return result ?? false;
  }

  bool? condition(String? value, Map<String, dynamic> ce,
      {bool? patchResult, String? debugId}) {
    
    String? condValue = exchgValue(ce.v(C_VALUE)) ?? value;
    var exp = ce.v(C_EXP);
    if (exp is String) {
      exp = exchgValue(exp);
    } else if (exp is List) {
      for (int i = 0; i < exp.length; i++) {
        exp[i] = exchgValue(exp[i]);
      }
    }

    switch (strLowcase(ce.v(C_EXP_TYPE) ?? "")) {
      case "isnull":
      // {
      //       "expType": "isnull",
      //       "isnot": false
      // }
        patchResult =
            relationAction(patchResult, notAction(ce.v(C_IS_NOT),condValue == null), ce.v(C_RELATION));
        break;
      case "isempty":
      // {
      //       "expType": "isempty",
      //       "isnot": true
      // }
        patchResult = relationAction(
            patchResult, notAction(ce.v(C_IS_NOT),condValue?.isEmpty ?? true), ce.v(C_RELATION));
        break;
      case "in":
        // {
        //       "expType": "in",
        //       "exp": "jpg,png,jpeg,gif,bmp",
        //       "isnot": true
        // }
        patchResult = relationAction(patchResult,
            notAction(ce.v(C_IS_NOT),(exp as String).split(",").contains(condValue)), ce.v(C_RELATION));
        break;
      case "compare":
        // {
        //       "expType": "compare",
        //       "exp": "viewthread.php",
        //       "value": "{system.platform}", //* 存在则优先处理
        //       "isnot": true
        // }
        patchResult = relationAction(
            patchResult,
            notAction(ce.v(C_IS_NOT), condValue?.compareTo(exp) == 0),
            ce.v(C_RELATION));
        break;
      case "contain":
        // {
        //       "expType": "contain",
        //       "exp": "viewthread.php",   //  exp: [jpg, gif, bmp, png, jpeg],
        //       "source": "{system.platform}", //* 存在则优先处理
        //       "relation": "and"
        //       "not": true
        // }
        if (exp is String) {
          patchResult = relationAction(
              patchResult,
              notAction(ce.v(C_IS_NOT), condValue?.contains(exp) ?? false),
              ce.v(C_RELATION));
        } else if (exp is List) {
          bool listResult = false;
          exp.forEach((element) {
            listResult = (condValue?.contains(element) ?? false) || listResult;
          });
          patchResult = relationAction(patchResult,
              notAction(ce.v(C_IS_NOT), listResult), ce.v(C_RELATION));
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
