final List<String> C_PROCESS_NAME=["processname","functionname","name"];
final List<String> C_VALUE_DEFINE=["globalvalue","valuedefine","values"];
final List<String> C_FUNCTION_DEFINE=["functiondefine","funcdef","procdef"];

final List<String> C_PROCESS=["valueprocess","process","loopprocess","beginsegment","proc","func"];
final List<String> C_PRE_PROCESS=["preprocess","preproc","prefunc"];
// final List<String> C_SPLIT_PROCESS=["splitprocess"];
final List<String> C_TRUE_PROCESS=["trueprocess","true"];
final List<String> C_FALSE_PROCESS=["falseprocess","false"];
final List<String> C_MULTI_VALUE_BUILDER=["valuesbuilder","vbuild"];
final List<String> C_MULTI_PROCESS=["multiprocess","splitprocess","mproc","mfunc"];
// final List<String> C_FUNCTION_NAME=["functionname"];
final List<String> C_ACT=["action","act","cmd","a"];
final List<String> C_VALUE=["value"];
final List<String> C_FROM=["from"];
final List<String> C_TO=["to"];
final List<String> C_START=["start","begin","front"];
final List<String> C_END=["end","back"];
final List<String> C_LENGTH=["length","len"];
// final List<String> C_FRONT=["front"];
// final List<String> C_BACK=["back"];
final List<String> C_INDEX=["index","idx","i"];
// final List<String> C_PATTERN=["pattern"];
final List<String> C_VALUE_NAME=["valuename","keyname","vname"];
final List<String> C_EXP=["exp","pattern","separator"];
// final List<String> C_KEY_NAME=[];
final List<String> C_FILE_NAME=["filename","fname","filepath","fpath"];
final List<String> C_FILE_MODE=["filemode","fmode"];
final List<String> C_URL=["url"];
final List<String> C_CHARSET=["charset"];
final List<String> C_BODY=["body"];
// final List<String> C_QUERY=["queryparameters"];
final List<String> C_HEADERS=["headers"];
final List<String> C_METHOD=["method"];
final List<String> C_TYPE=["type"];
final List<String> C_SCRIPT=["script"];
final List<String> C_PROPERTY=["property","prop"];
final List<String> C_LIST=["list"];
final List<String> C_RANGE=["range"];
final List<String> C_COND_EXPS=["condexps","cexps"];
final List<String> C_PARAMETERS=["parameters","queryparameters","params"];
final List<String> C_CODE=["code"];
final List<String> C_EXCEPT=["except","exc"];
final List<String> C_EXP_TYPE=["exptype","etype"];
final List<String> C_RELATION=["relation","rel"];
final List<String> C_IS_ASC=["isasc","asc"];
final List<String> C_IS_NOT=["isnot","not"];
final List<String> C_IS_ENCODE=["isencode","encode"];

extension ValueExtension on Map<String, dynamic> {
  dynamic v(List<String> action, {dynamic whenNull}) {
    for (String act in action){
      if(this[act]!=null)return this[act];
    }
    return whenNull;
  }
}