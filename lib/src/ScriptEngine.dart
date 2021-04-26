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
    assert(scriptSource != null);
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

    if (scriptJson["beginSegment"] == null) {
      logger.warning("找不到[beginSegment]段落，执行结束！");
      return;
    }

    processName = scriptJson["processName"];

    globalValue = Map.castFrom(scriptJson["globalValue"]);
    reloadGlobalValue();

    functions = Map.castFrom(scriptJson["functionDefine"]);
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
        // switch (valueName) {
        //   case "url":
        //     ret = ret.replaceFirst(valueExp, url);
        //     break;
        //   case "bookinfo.novelHome":
        //     ret = ret.replaceFirst(valueExp, selectedBookInfo.novelHome);
        //     break;
        //   case "bookinfo.novelName":
        //     ret = ret.replaceFirst(valueExp, selectedBookInfo.novelName);
        //     break;
        //   default:
        if (getValue(valueName) == null) break;
        ret = ret.replaceFirst(valueExp, getValue(valueName));
        // break;
        // }
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
  }

  String removeValue(String key) => tValue.remove(key ?? "");

  dynamic getValue(String key) => tValue[key ?? ""];

  Future<String> singleProcess(String value, dynamic procCfg) async {
    if (procCfg != null) {
      String debugId = genKey(lenght: 8);
      for (var act in procCfg ?? []) {
        String preErrorProc=value;
        value = await action(value, act, debugId: debugId);
        if (value == null) {
          logger.warning("--$debugId--[Return null,Abort this singleProcess! Please check singleAction($act,$preErrorProc)");
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

  dynamic action(String value, dynamic actCfg, {String debugId = ""}) async {
    String ret;
    bool refreshValue=true;
    if (debugMode) logger.fine("--$debugId--💃action($actCfg)");
    if (debugMode) logger.finest("--$debugId--value : $value");

    try {
      switch (actCfg["action"]) {
        case "print":
          //           {
          //             "action": "print",
          //             "value": "url"   //*
          //           }
          logger.info(exchgValue(actCfg["value"] ?? value));
          refreshValue=false;
          break;
        case "replace":
          //             {
          //               "action": "replace",
          //               "from": "<(\\S+)[\\S| |\\n|\\r]*?>[^<]*</\\1>",
          //               "to": ""
          //             },
          ret = value.replaceAll(RegExp(actCfg["from"]), actCfg["to"]);
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
          String f = actCfg["front"] ?? "";
          String b = actCfg["back"] ?? "";
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
          ret = value.split(actCfg["pattern"])[actCfg["index"]];
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
          if (actCfg["valueName"] != null) {
            setValue(
                actCfg["valueName"],
                actCfg["value"] ??
                    await singleProcess(value, actCfg["valueProcess"] ?? []));
          }
          refreshValue=false;
          break;
        case "getValue":
          //            {
          //              "action": "getValue",
          //              "valueName": "url",   //*
          //              "value": "{novelName}-{writer}"   //*
          //            }
          //            value和valueName两者只有其中一个生效，value的优先级更高
          ret = exchgValue(actCfg["value"]) ?? getValue(actCfg["valueName"]);
          break;
        case "removeValue":
          //            {
          //              "action": "removeValue",
          //              "valueName": "pageUrl"
          //            }
          if (actCfg["valueName"] != null) removeValue(actCfg["valueName"]);
          refreshValue=false;
          break;
        case "clearEnv":
          //            {
          //              "action": "clearEnv",
          //            }
          clear();
          refreshValue=false;
          break;
        case "push":
          //             {
          //               "action": "push"
          //             },
          tStack.add(value);
          refreshValue=false;
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
          if (actCfg["keyName"] != null)
            ret = jsonDecode(value)[actCfg["keyName"]];
          break;
        case "readFile":
          //            {
          //               "action": "readFile",
          //               "fileName": "{basePath}/file1.txt",
          //               "toValue": "txtfile"
          //             },
          if (actCfg["fileName"] != null) {
            String fileContent = readFile(exchgValue(actCfg["fileName"]));
            if (actCfg["toValue"] != null) {
              setValue(exchgValue(actCfg["toValue"]), fileContent);
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
          if (actCfg["fileName"] != null) {
            saveFile(exchgValue(actCfg["fileName"]),
                exchgValue(actCfg["saveContent"]) ?? value);
          }
          refreshValue=false;
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
          String htmlUrl = exchgValue(actCfg["url"]) ?? value;
          // logger.fine("htmlUrl=$htmlUrl");
          String body = exchgValue(actCfg["body"]);

          Encoding encoding =
              "gbk".compareTo(actCfg["charset"]) == 0 ? gbk : utf8;

          //todo:queryParameters的使用好像还有问题
          Map<String, dynamic> queryParameters =
              Map.castFrom(actCfg["queryParameters"] ?? {});
          queryParameters.forEach((key, value) {
            if (value is String) {
              queryParameters[key] = Uri.encodeQueryComponent(exchgValue(value),
                  encoding: encoding);
            }
          });

          Map<String, dynamic> headers = Map.castFrom(actCfg["headers"] ?? {});

          RequestMethod method =
              "post".compareTo(actCfg["method"] ?? "get") == 0
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
          switch (actCfg["type"]) {
            case "dom":
              var tmp =
                  HtmlParser(value).parse().querySelector(actCfg["script"]);
              if (tmp != null) {
                switch (actCfg["property"] ?? "innerHtml") {
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
                    ret = tmp.attributes[actCfg["property"]] ?? "";
                }
              } else
                ret = "";
              break;
            case "xpath":
              ret = XPath.source(value).query(actCfg["script"])?.get() ?? "";
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
          switch (actCfg["type"]) {
            case "dom":
              var tmps =
                  HtmlParser(value).parse().querySelectorAll(actCfg["script"]);
              var tmp;
              if (tmps?.length ?? 0 > 0)
                tmp = tmps.elementAt(actCfg["index"] ?? 0);
              if (tmp != null) {
                switch (actCfg["property"] ?? "innerHtml") {
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
                    ret = tmp.attributes[actCfg["property"]] ?? "";
                }
              } else
                ret = "";
              break;
            case "xpath":
              var tmps = XPath.source(value).query(actCfg["script"])?.list();
              if (tmps?.length > 0)
                ret = tmps.elementAt(actCfg["index"] ?? 0);
              else
                ret = "";
              break;
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
          if (conditionPatch(
              exchgValue(actCfg["source"]) ?? value, actCfg["exp"],
              debugId: debugId)) {
            ret = await singleProcess(value, actCfg["trueProcess"]);
          } else {
            ret = await singleProcess(value, actCfg["falseProcess"]);
          }
          break;
        case "break":
          ret = null;
          break;
        case "exit":
          exit(actCfg["code"] ?? 0);
          break;
        case "callMultiProcess":
          //    {
          //       "action": "callMultiProcess",
          //       "multiProcess": []
          //    }
          var multiResult =
              (await multiProcess([value], actCfg["multiProcess"]));
          setValue(MULTIRESULT, multiResult);
          ret = multiResult.toString();
          break;
        case "callFunction":
          if (functions[actCfg["functionName"]] != null)
            ret = await singleProcess(value, functions[actCfg["functionName"]]);
          else {
            logger
                .warning("Function ${actCfg["functionName"]} is not found"); //
          }
          break;
        default:
          if (debugMode) logger.fine("Unknow config : [${actCfg.toString()}]");
          break;
      }
    } catch (e) {
      logger.warning(e.toString());
      logger.warning("--$debugId--💃action($actCfg,$value)");
      // throw e;
    }
    if (debugMode && ret!=null) logger.fine("--$debugId--⚠️️result[${shortString(ret)}]");
    // if (debugMode) logger.finest("--$debugId--⚠️️result[$ret]");

    if(!refreshValue)ret=value;

    return ret;
  }

  Future<List<String>> multiProcess(List<String> objs, dynamic procCfg) async {
    String debugId = genKey(lenght: 8);
    if (procCfg != null) {
      for (var act in procCfg) {
        List<String> preErrorProc=objs;
        objs = await multiAction(objs, act, debugId: debugId);
        if(objs==null){
          logger.warning("--$debugId--[Return null,Abort this MultiProcess! Please check multiAction($act,$preErrorProc)");
          break;
        }
      }
      setValue(MULTIRESULT, objs);
    }
    return objs;
  }

  Future<List<String>> multiAction(List<String> value, dynamic actCfg,
      {String debugId = ""}) async {
    List<String> ret;
    if (debugMode) logger.fine("--$debugId--🎾multiAction($actCfg,${shortString(value.toString())})");
    if (debugMode) logger.finest("--$debugId--value : $value)");
    switch (actCfg["action"]) {
      case "multiSelector":
        switch (actCfg["type"]) {
          case "dom":
            //            {
            //               "action": "multiSelector",
            //               "type": "dom",
            //               "script": ".sbintro"
            //             }
            ret = domList2StrList(HtmlParser(value[0])
                .parse()
                .querySelectorAll(actCfg["script"]));
            break;
          case "xpath":
            //          {
            //             "action": "multiSelector",
            //             "type": "xpath",
            //             "script": "//a/@href"
            //           }
            ret = XPath.source(value[0]).query(actCfg["script"]).list();
            break;
        }
        break;
      case "remove":
        //          {
        //             "action": "remove",
        //             "index": 0,    //*
        //             "except": 2    //*
        //           }
        //          index优先级更高
        var index = actCfg["index"];
        if (index != null) {
          if (index is int) value.removeAt(index);
          if (index is String) {
            if ("first".compareTo(index.toLowerCase()) == 0) value.removeAt(0);
            if ("last".compareTo(index.toLowerCase()) == 0) value.removeLast();
          }
        } else if (actCfg["except"] != null && actCfg["except"] is int) {
          value = [value.removeAt(actCfg["except"])];
        }
        ret = value;
        break;
      case "sort":
        //            {
        //               "action": "sort",
        //               "asc": true
        //             },
        if (actCfg["asc"] ?? true) {
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
        if (actCfg["end"] != null) {
          ret = value.sublist(actCfg["begin"] ?? 0, actCfg["end"]);
        } else {
          ret = value.sublist(actCfg["begin"] ?? 0);
        }
        break;
      case "saveMultiToFile":
        //            {
        //               "action": "saveMultiToFile",
        //               "fileName": "{basePath}/file1.txt"
        //             },
        File saveFile;
        if (actCfg["fileName"] != null) {
          saveFile = File(exchgValue(actCfg["fileName"]));
          if (!saveFile.existsSync()) saveFile.createSync(recursive: true);
          for (String line in value) {
            saveFile.writeAsStringSync(line,
                mode: FileMode.append, encoding: utf8, flush: true);
          }
          ret = value;
        }
        break;
      case "foreach":
        //        {
        //           "action": "foreach",
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
        List<String> tmpList = [];

        for (String one in value) {
          ///如果单条处理存在则先处理
          if (actCfg["eachProcess"]?.length > 0)
            tmpList.add(await singleProcess(one, actCfg["eachProcess"]));

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
        if (debugMode) logger.warning("Unknow config : [${actCfg.toString()}]");
        break;
    }
    if (debugMode) logger.fine("--${debugId ?? ""}--🧩result[${shortString(ret.toString())}]");
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

  bool condition(String value, dynamic condExp,
      {bool patchResult, String debugId}) {
    String exp = exchgValue(condExp["exp"]);
    switch (condExp["expType"]) {
      case "compare":
        patchResult = relationAction(
            patchResult, value.compareTo(exp) == 0, condExp["relation"]);
        break;
      case "contain":
        patchResult = relationAction(
            patchResult, value.contains(exp), condExp["relation"]);
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
          "--${debugId ?? ""}--⚖️condition($condExp,$value)--🔐result[$patchResult]");
    return patchResult;
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
