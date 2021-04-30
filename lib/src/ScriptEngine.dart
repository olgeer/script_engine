import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart';
import 'package:logging/logging.dart';
import 'package:xpath_parse/xpath_selector.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'actionCollect.dart';
import 'HtmlCodec.dart';

class ScriptEngine {
  Map<String, dynamic> tValue = {}; //配置运行时临时变量表
  List<String> tStack = []; //配置运行时堆栈
  Map<String, dynamic> globalValue;
  Map<String, dynamic> functions;
  bool debugMode;

  String script;
  Map<String, dynamic> scriptJson;
  String processName;
  final Logger logger = Logger("ScriptEngine");

  final String MULTIRESULT = "multiResult";
  final String SINGLERESULT = "singleResult";

  ///初始化json脚本引擎，暂时一个脚本对应一个引擎，拥有独立的变量及堆栈空间
  ///scriptSource可以是String，Uri，File等类型，指向json脚本内容
  ScriptEngine(dynamic scriptSource, {this.debugMode = false}) {
    // assert(scriptSource != null);
    initScript(scriptSource);
  }

  void initScript(dynamic scriptSrc) async {
    if (scriptSrc is Uri) {
      if (scriptSrc.isScheme("file")) script = readFile(scriptSrc.path);
      if (scriptSrc.isScheme("https"))
        script = await getHtml(scriptSrc.toString());
      // if(scriptSrc.isScheme("asset"))script = await rootBundle.loadString(scriptSrc.path);
    }
    if (scriptSrc is File) {
      script = readFile(scriptSrc);
    }
    if (scriptSrc is String) {
      script = scriptSrc;
    }
    scriptJson = json.decode(script ?? "{}");

    // if (scriptJson["beginSegment"] == null) {
    //   logger.warning("找不到[beginSegment]段落，执行结束！");
    //   return;
    // }

    processName = scriptJson["processName"]??"DefaultProcess";

    if (scriptJson["globalValue"] != null) {
      globalValue = Map.castFrom(scriptJson["globalValue"]);
      reloadGlobalValue();
    }

    functions = Map.castFrom(scriptJson["functionDefine"]??{});
  }

  ///直接执行脚本，所有处理均包含在脚本内，对最终结果不太关注
  Future run() async => await singleProcess("", scriptJson["beginSegment"]);

  ///调用某函数方法，期待脚本返回中间结果，以便后续程序使用
  ///isMultiResult参数为true时，返回最后一组结果列表，为false时，返回最终的字符串结果
  Future call(String functionName, {bool isMultiResult = false}) async {
    await singleProcess("", functions[functionName]);
    return isMultiResult ? getValue(MULTIRESULT) : getValue(SINGLERESULT);
  }

  void clear() {
    tValue.clear();
    tStack.clear();
    logger.fine("$processName is clear.");
  }

  void reloadGlobalValue() {
    globalValue?.forEach((key, value) {
      setValue(key, value);
    });
  }

  String exchgValue(String exp) {
    RegExp valueExp = RegExp('{([^}]+)}');
    String ret = exp;

    if (exp != null) {
      while (valueExp.hasMatch(ret)) {
        String valueName = valueExp.firstMatch(ret).group(1);
        String repValue;
        switch (valueName) {
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
            var v=getValue(valueName);
            if (v == null) break;
            else if(v is String){
              repValue = v;
            }else
              repValue = v.toString();
            break;
        }
        if (repValue != null) ret = ret.replaceFirst(valueExp, repValue);
      }
    }
    return ret;
  }

  void setValue(String key, dynamic value) {
    assert(key != null, "key must NOT null");
    if (tValue[key] != null) {
      tValue[key] = value;
    } else {
      tValue.putIfAbsent(key, () => value);
    }
    logger.finer("Set value($key) to $value");
  }

  String removeValue(String key) => tValue.remove(key ?? "");

  dynamic getValue(String key) => tValue[key ?? ""];

  Future<String> singleProcess(String value, dynamic procCfg) async {
    if (procCfg != null) {
      String debugId = genKey(lenght: 8);
      for (var act in procCfg ?? []) {
        String preErrorProc = value;
        setValue("this", value);
        value = await action(value, act, debugId: debugId);
        if (value == null) {
          logger.warning(
              "--$debugId--[Return null,Abort this singleProcess! Please check singleAction($act,$preErrorProc)");
          break;
        }
      }
      // tValue.clear(); //确保产生的变量仅用于本process内
      // tStack.clear();
      setValue(SINGLERESULT, value);
      return value;
    } else
      return null;
  }

  dynamic action(String value, dynamic ac, {String debugId = ""}) async {
    String ret;
    bool refreshValue = true;
    if (debugMode) logger.fine("--$debugId--💃action($ac)");
    if (debugMode) logger.finest("--$debugId--value : $value");

    try {
      switch (ac["action"]) {
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
          ret = value.replaceAll(RegExp(ac["from"]), ac["to"]);
          break;
        case "htmlDecode":
          //           {
          //             "action": "htmlDecode"
          //           }
          ret = HtmlCodec().decode(value);
          break;
        case "concat":
          //           {
          //             "action": "concat",
          //             "front": "<table>",
          //             "back": "</table>"
          //           }
          String f = ac["front"] ?? "";
          String b = ac["back"] ?? "";
          f = exchgValue(f);
          b = exchgValue(b);
          ret = "$f$value$b";
          break;
        case "split":
          //             {
          //               "action": "split",
          //               "pattern": "cid=",
          //               "index": 1
          //             },
          if (ac["index"] is int)
            ret = value.split(ac["pattern"])[ac["index"]];
          else if (ac["index"] is String) {
            switch (ac["index"]) {
              case "first":
                ret = value.split(ac["pattern"]).first;
                break;
              case "last":
                ret = value.split(ac["pattern"]).last;
            }
          }
          break;
        case "trim":
          //            {
          //              "action": "trim"
          //            }
          ret = value.trim();
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
                ac["value"] ??
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
          //            value和valueName两者只有其中一个生效，value的优先级更高
          ret = exchgValue(ac["exp"]) ?? getValue(ac["value"]);
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
          if (ac["keyName"] != null) ret = jsonDecode(value)[ac["keyName"]];
          break;
        case "readFile":
          //            {
          //               "action": "readFile",
          //               "fileName": "{basePath}/file1.txt",
          //               "toValue": "txtfile"
          //             },
          if (ac["fileName"] != null) {
            String fileContent = readFile(exchgValue(ac["fileName"]));
            if (ac["toValue"] != null) {
              setValue(exchgValue(ac["toValue"]), fileContent);
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
          //             },
          if (ac["fileName"] != null) {
            saveFile(exchgValue(ac["fileName"]),
                exchgValue(ac["saveContent"]) ?? value);
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
            saveUrlFile(exchgValue(ac["url"]),
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
          String htmlUrl = exchgValue(ac["url"]) ?? value;
          // logger.fine("htmlUrl=$htmlUrl");
          String body = exchgValue(ac["body"]);

          Encoding encoding = "gbk".compareTo(ac["charset"]) == 0 ? gbk : utf8;

          //todo:queryParameters的使用好像还有问题
          Map<String, dynamic> queryParameters =
              Map.castFrom(ac["queryParameters"] ?? {});
          queryParameters.forEach((key, value) {
            if (value is String) {
              queryParameters[key] = Uri.encodeQueryComponent(exchgValue(value),
                  encoding: encoding);
            }
          });

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
              debugMode: debugMode);
          break;
        case "selector":
          //            {
          //               "action": "selector",
          //               "type": "dom",
          //               "script": "[property=\"og:novel:book_name\"]",
          //               "property": "content"
          //             }
          //            {
          //               "action": "selector",
          //               "type": "xpath",
          //               "script": "//p[3]/span[1]/text()"
          //             },
          switch (ac["type"]) {
            case "dom":
              var tmp = HtmlParser(value)
                  .parse()
                  .querySelector(exchgValue(ac["script"]));
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
              ret = XPath.source(value).query(ac["script"])?.get() ?? "";
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
              if (tmps?.length ?? 0 > 0) tmp = tmps.elementAt(ac["index"] ?? 0);
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
              var tmps = XPath.source(value).query(ac["script"])?.list();
              if (tmps?.length > 0)
                ret = tmps.elementAt(ac["index"] ?? 0);
              else
                ret = "";
              break;
          }
          break;
        case "for":
          // {
          //   "action": "for",
          //   "valueName": "ipage",
          //   "type": "list",
          //   "range": [1,10],     //*
          //   "list": [1,2,4,5,7], //*
          //   "loopProcess": []
          // }
          var loopCfg = ac["loopProcess"];
          if (loopCfg != null && (ac["list"] != null || ac["range"] != null)) {
            switch (ac["type"]) {
              case "list":
                if (ac["list"] != null) {
                  for (int i in ac["list"]) {
                    setValue(ac["valueName"], i);
                    ret = await singleProcess(value, loopCfg);
                  }
                }
                break;
              case "range":
                if (ac["range"] != null) {
                  for (int i = ac["range"][0]; i < ac["range"][1]; i++) {
                    setValue(ac["valueName"], i.toString());
                    ret = await singleProcess(value, loopCfg);
                  }
                }
                break;
            }
          }
          break;

        ///条件分支执行
        case "condition":
          //     {
          //       "action": "condition",
          //       "exp": {
          //         "expType": "contain",
          //         "exp": "搜索结果",
          //         "source":"{title}"     //source.contain(exp)
          //       },
          //       "trueProcess": [],
          //       "falseProcess": []
          //     }
          if (conditionPatch(exchgValue(ac["source"]) ?? value, ac["exp"],
              debugId: debugId)) {
            ret = await singleProcess(value, ac["trueProcess"]);
          } else {
            ret = await singleProcess(value, ac["falseProcess"]);
          }
          break;
        case "break":
          ret = null;
          break;
        case "exit":
          exit(ac["code"] ?? 0);
          break;
        case "callMultiProcess":
          //    {
          //       "action": "callMultiProcess",
          //       "multiProcess": []
          //    }
          var multiResult = (await multiProcess([value], ac["multiProcess"]));
          setValue(MULTIRESULT, multiResult);
          ret = multiResult.toString();
          break;
        case "callFunction":
          if (functions[ac["functionName"]] != null) {
            if (ac["parameters"] != null && ac["parameters"] is Map) {
              Map<String, dynamic> params = Map.castFrom(ac["parameters"]);
              params.forEach((key, value) {
                setValue(key, value);
              });
            }
            ret = await singleProcess(
                value, functions[ac["functionName"]]["process"]);
          } else {
            logger.warning("Function ${ac["functionName"]} is not found"); //
          }
          break;
        default:
          if (debugMode) logger.fine("Unknow config : [${ac.toString()}]");
          break;
      }
    } catch (e) {
      logger.warning(e.toString());
      logger.warning("--$debugId--💃action($ac,$value)");
      // throw e;
    }
    if (debugMode && ret != null)
      logger.fine("--$debugId--⚠️️result[${shortString(ret)}]");
    // if (debugMode) logger.finest("--$debugId--⚠️️result[$ret]");

    if (!refreshValue) ret = value;

    return ret;
  }

  Future<List<String>> multiProcess(List<String> objs, dynamic procCfg) async {
    String debugId = genKey(lenght: 8);
    if (procCfg != null) {
      for (var act in procCfg) {
        List<String> preErrorProc = objs;
        setValue("thisObjs", objs);
        objs = await multiAction(objs, act, debugId: debugId);
        if (objs == null) {
          logger.warning(
              "--$debugId--[Return null,Abort this MultiProcess! Please check multiAction($act,$preErrorProc)");
          break;
        }
      }
      setValue(MULTIRESULT, objs);
    }
    return objs;
  }

  Future<List<String>> multiAction(List<String> value, dynamic ac,
      {String debugId = ""}) async {
    List<String> ret;
    if (debugMode)
      logger.fine(
          "--$debugId--🎾multiAction($ac,${shortString(value.toString())})");
    if (debugMode) logger.finest("--$debugId--value : $value)");
    switch (ac["action"]) {
      case "multiSelector":
        switch (ac["type"]) {
          case "dom":
            //            {
            //               "action": "multiSelector",
            //               "type": "dom",
            //               "script": ".sbintro"
            //             }
            ret = domList2StrList(
                HtmlParser(value[0]).parse().querySelectorAll(ac["script"]));
            break;
          case "xpath":
            //          {
            //             "action": "multiSelector",
            //             "type": "xpath",
            //             "script": "//a/@href"
            //           }
            ret = XPath.source(value[0]).query(ac["script"]).list();
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
        } else if (ac["condition"] != null) {
          value.removeWhere(
              (element) => conditionPatch(element, ac["condition"]));
        }
        ret = value;
        break;
      case "sort":
        //            {
        //               "action": "sort",
        //               "asc": true
        //             },
        if (ac["asc"] ?? true) {
          value.sort((l, r) => l.compareTo(r));
        } else {
          value.sort((l, r) => r.compareTo(l));
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
          saveFile = File(exchgValue(ac["fileName"]));
          if (!saveFile.existsSync()) saveFile.createSync(recursive: true);
          for (String line in value) {
            saveFile.writeAsStringSync(line,
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
        List<String> tmpList = [];

        for (String one in value) {
          ///如果单条处理存在则先处理
          if (ac["eachProcess"]?.length??0 > 0)
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
      default:
        if (debugMode) logger.warning("Unknow config : [${ac.toString()}]");
        break;
    }
    if (debugMode)
      logger
          .fine("--${debugId ?? ""}--🧩result[${shortString(ret.toString())}]");
    // if (debugMode) logger.finest("--${debugId ?? ""}--🧩result[$ret]");
    return ret;
  }

  bool conditionPatch(String value, dynamic condCfg, {String debugId}) {
    bool result;
    if (condCfg != null) {
      for (var cond in condCfg) {
        result = condition(value, cond, patchResult: result, debugId: debugId);
      }
    }
    return result;
  }

  bool condition(String value, dynamic ce, {bool patchResult, String debugId}) {
    var exp = ce["exp"];
    if(exp is String){
      exp=exchgValue(exp);
    }else if(exp is List){
      for(int i=0;i<exp.length;i++){
        exp[i]=exchgValue(exp[i]);
      }
    }
    switch (ce["expType"]) {
      case "isNull":
        patchResult =
            relationAction(patchResult, value == null, ce["relation"]);
        break;
      case "isEmpty":
        patchResult =
            relationAction(patchResult, value.isEmpty, ce["relation"]);
        break;
      case "in":
        // {
        //       "expType": "in",
        //       "exp": "jpg,png,jpeg,gif,bmp",
        //       "not": true
        // }
        patchResult =
            relationAction(patchResult, exp.split(",").contains(value), ce["relation"]);
        break;
      case "compare":
        // {
        //       "expType": "compare",
        //       "exp": "viewthread.php",
        //       "not": true
        // }
        patchResult = relationAction(patchResult,
            notAction(ce["not"], value.compareTo(exp) == 0), ce["relation"]);
        break;
      case "contain":
        // {
        //       "expType": "contain",
        //       "exp": "viewthread.php",
        //       "relation": "and"
        // }
        if(exp is String){
          patchResult = relationAction(patchResult,
            notAction(ce["not"], value.contains(exp)), ce["relation"]);
        }else if(exp is List){
          bool listResult=false;
          exp.forEach((element) {
            listResult=value.contains(element) ||listResult;
          });
          patchResult = relationAction(patchResult,
              notAction(ce["not"], listResult), ce["relation"]);
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
          "--${debugId ?? ""}--⚖️condition($ce,$value)--🔐result[$patchResult]");
    return patchResult;
  }

  bool notAction(bool isNot, bool value) {
    return isNot ?? false ? !value : value;
  }

  bool relationAction(bool origin, bool value, String relation) {
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
