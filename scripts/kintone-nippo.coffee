# Description:
#   kintoneの日報アプリにデータを投稿します。
# 
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_CYBOZU_URI
#   HUBOT_CYBOZU_NIPPO_AUTH
#   HUBOT_CYBOZU_NIPPO_APPID
#
# Commands:
#   hubot 日報 - 今日作成された日報を一覧します。
#   hubot <お疲れさまなど> - 今日の日報を作成する.
#
# Author:
#   masataka.takeuchi

endpoint = process.env.HUBOT_CYBOZU_URI
auth     = process.env.HUBOT_CYBOZU_NIPPO_AUTH
appId    = process.env.HUBOT_CYBOZU_NIPPO_APPID

if endpoint? then endpoint = endpoint.replace(/\/$/, "")

workField  = "文字列__複数行_"
scoreField = "ドロップダウン_0"
memoField  = "文字列__複数行__0"
fileField  = "添付ファイル"

module.exports = (robot) ->
  brain = robot.brain
    
  robot.hear /日報/i, (msg) ->
    findTodayNippo msg, "", (records) ->
      if records?
        msg.send (msgNippo record for record in records).join("\n")
      else
        msg.send msgNotFound

  robot.respond "file", (msg) ->
    msg.download msg.json, (path) ->
      stateAction brain, msg, path
    msg.finish()

  robot.respond "select", (msg) ->
    if msg.json.response?
      stateAction brain, msg, msg.json.options[msg.json.response]
    msg.finish()

  robot.respond /((.|[\n\r])*)/, (msg) ->
    return if msg.match[1] == "日報"
    stateAction brain, msg, msg.match[1]

  robot.join (msg) ->
    # 自分自身ではなく、会話相手のユーザ情報に変換。
    [userA, userB] = msg.message.roomUsers
    msg.message.user = if msg.message.user.id == userA.id then userB else userA
    
    setState brain, msg, "idle"
    stateAction brain, msg, ""

## State Pattern

currentState = (brain, msg) ->
  st = brain.get userCode(msg)
  if not st? or (new Date().getTime() - parseInt(st.split("@")[1]) > 3600 * 1000)
    "idle" # 一定時間を過ぎたら状態を戻す。
  else
    st.split("@")[0]

setState = (brain, msg, st) ->
  brain.set userCode(msg), st + "@" + (new Date().getTime())

stateAction = (brain, msg, text) ->
  console.log "text: " + text
  st = currentState(brain, msg)
  console.log "state:" + st
  act = statuses[st]
  if act?
    next = act(msg, text)
    if next?
      setState brain, msg, next
  else
    msg.send msgStatusError
    setState brain, msg, "idle"


## Nippo Statues

statuses = {
  idle : (msg) ->
    msg.send
      stamp_set: 3
      stamp_index: "1152921507291203590"
      text: msgStartNippo msg
    "input_done"
  input_done : (msg, text) ->
    if text.match(/^(\.|．|。|次へ)$/)
      msg.send msgInputScore
      "input_score"
    else
      addTodayNippo msg, workField, "・" + text, (record) ->
        if record?
          msg.send msgInputContinue "業務"
        else
          msg.send msgUpdateFailed
      "input_done"
  input_score: (msg, text) ->
    score = parseInt(text)
    if 0 <= score and score <= 100
      console.log score
      v = switch
        when score < 30  then "着手直後"
        when score < 50  then "30%"
        when score < 80  then "50%"
        when score < 100 then "80%"
        else "達成"
      console.log v
      addTodayNippo msg, scoreField, v
      , (record) ->
        if record?
          msg.send msgInputMemo
        else
          msg.send msgUpdateFailed
      "input_memo"
    else
      msg.send msgInputScore
      "input_score"
  input_memo : (msg, text) ->
    if text.match(/^(.|．|。|次へ)$/)
      getTodayNippo msg, "日付", (record) ->
        if record?
          msg.send
            stamp_set: 3
            stamp_index: "1152921507291204249"
            text: msgEndNippo msg, record
          msg.leave()
        else
          msg.send msgUpdateFailed
      "idle"
    else
      field = if msg.json?.url? then fileField else memoField
      if field == memoField
        if text.match /^今ココ/    # iOS版は改行が入るので削除しておく
          text = text.replace(/[\r\n]/g, " ").replace(/http/, "\nhttp")
        text = text + "\n"  # 段落毎に改行
      addTodayNippo msg, field, text, (record) ->
        if record?
          msg.send msgInputContinue "所感・学び"
        else
          msg.send msgUpdateFailed
      "input_memo"
}


## Messages

msgStartNippo = (msg) ->
  d = new Date()
  y = d.getYear()
  if y < 2000 then y += 1900
  today = "#{y}/#{d.getMonth() + 1}/#{d.getDate()}"
  [
    "#{userName(msg)}さん、お疲れ様です。",
    "本日(#{today})はどんな業務をしましたか？",
    "1件1メッセージでお願いします。"
  ].join("\n")

msgInputContinue = (title) ->
  question: "他にも#{title}があれば教えて下さい。\nなければ「。」もしくは「次へ」を選んで下さい。"
  options: ["次へ"]

msgInputScore = 
  question: "目標達成度はどのくらいですか？\n数値で教えて下さい。"
  options: ["0", "30", "50", "80", "100"]

msgInputMemo = 
  [
    "所感・学びを教えて下さい。"
    "画像や動画、今ココスタンプも使えます。"
    "メッセージを分けることで複数の報告ができます。"
  ].join("\n")

msgEndNippo = (msg, record) ->
  [
    "業務報告をkintoneに書き込みました。"
    "#{endpoint.replace('/v1', '/'+appId)}/show#record=#{record.レコード番号.value}"
    "#{userName(msg)}さん、本日の業務、お疲れ様でした。"
  ].join("\n")

msgStatusError = 
  [
    "申し訳ありません。状態がおかしくなりました。",
    "もういちど始めからやり直して下さい。"
  ].join("\n")

msgNotFound = 
  "今日の日報はまだ報告されていません。"

msgUpdateFailed = 
  "更新に失敗しました。"

msgNippo = (record) ->
  [ record.作成者.value.name + " (" + record[scoreField].value + ")",
    "#{endpoint.replace('/v1', '/'+appId)}/show#record=" + record.レコード番号.value
    #"[業務内容]",
    record[workField].value,
    #"[所感、学び]",
    #record[memoField].value,
    ""
  ].join("\n")


## user object

userName = (msg) ->
  msg.message.user.name

userCode = (msg) ->
  [name, domain] = msg.message.user.email.split "@"
  name


## Kintone Access

findTodayNippo = (msg, query, cb) ->
  msg.http("#{endpoint}/records.json")
    .header("X-Cybozu-Authorization", auth)
    .query(
      app: appId
      query: " (日付 = TODAY())"
      )
    .get() (err, res, body) ->
      result = JSON.parse body
      if result? and result.records? and result.records.length > 0
        cb result.records
      else
        cb null

addTodayNippo = (msg, field, text, cb) ->
  getTodayNippo msg, field, (record) ->
    updateNippo msg, record, field, text, cb

getTodayNippo = (msg, field, cb) ->
  msg.http("#{endpoint}/records.json")
    .header("X-Cybozu-Authorization", auth)
    .query(
      app: appId
      query: "(作成者 in (\"#{userCode(msg)}\")) and (日付 = TODAY()) limit 1"
      "fields[0]": field
      "fields[1]": "レコード番号"
      "fields[2]": "$revision"
      )
    .get() (err, res, body) ->
      result = JSON.parse body
      if result? and result.records? and result.records.length > 0
        cb result.records[0]
      else
        cb null

updateNippo = (msg, record, field, text, cb) ->
  if msg.json?.url?
    uploadFile msg, record, field, text, cb   # 先にファイルをアップロードする
    return

  query = 
      app: appId
      record: {}
  query.record[field] = value: text

  console.log "TARGET"
  console.log record
  if record?
    method = "PUT"
    query.id = record.レコード番号.value
    query.revision = record["$revision"].value
    query.record[field] =
      value:
        if record[field].type is "DROP_DOWN"
          text
        else if (oldText = record[field].value).length > 0
          if typeof(oldText) == 'string'
            oldText + "\n" + text
          else
            oldText.push text[0] # array
            oldText
        else
          text
  else
    method = "POST"
    query.record.作成者 = value: code: userCode(msg) 

  console.log "QUERY"
  console.log query

  msg.http("#{endpoint}/record.json")
    .header("X-Cybozu-Authorization", auth)
    .header("Content-Type", "application/json")
    .request(method, JSON.stringify(query)) (err, res, body) ->
      result = JSON.parse body
      console.log "RESULT"
      console.log result
      if result? and result.revision?
        cb result
      else
        msg.send result.message if result? and result.message
        cb null

uploadFile = (msg, record, field, path, cb) ->
  boundary="---------------------------bee48a285354"
  contentHeader = [
    "--#{boundary}"
    "Content-Disposition: form-data; name=\"file\"; filename=\"#{msg.json.name}\""
    "Content-Type: #{msg.json.content_type}"
    "\r\n"
  ].join("\r\n")
  contentFooter =
    "\r\n--#{boundary}--"
  contentLength = contentHeader.length + msg.json.content_size + contentFooter.length
    
  console.log "UPLOAD (#{contentLength}bytes)\n" + contentHeader + contentFooter
  
  msg.http("#{endpoint}/file.json")
    .header("X-Cybozu-Authorization", auth)
    .header("Content-Type", "multipart/form-data; boundary=#{boundary}")
    .header("Content-Length", contentLength)
    .post((err, req) ->
      require("fs").createReadStream(path)
        .on("open", () -> req.write contentHeader)
        .on("data", (chunk) -> req.write chunk)
        .on("end",  () -> req.write contentFooter; req.end())
    ) (err, res, body) ->
      console.log "UPLOAD RESULT\n" + body
      result = JSON.parse body
      if result?.fileKey?
        delete msg.json
        updateNippo msg, record, field, [result], cb
      else
        msg.send result.message if result? and result.message
        cb null
