# Changelog

## v1.9.6 - cpolar、消息平台初始化修复与网关状态同步

### 关键改动

- **新增 cpolar 可选组件**：在“可选组件”页面加入 cpolar，一站式提供安装、卸载、启动、停止、状态显示、Web 面板入口，以及安装过程中的实时日志滚动输出，方便直接在应用内完成穿透服务准备。
- **QQ / 微信接入初始化修复**：补齐 PRoot 原生运行时兜底逻辑，启动消息平台相关命令前会先准备 `libproot.so`、loader 与 DNS 配置；当部分设备未正确挂载原生库目录时，也能从 APK 中回退提取，修复插件初始化阶段的 `Native runtime binary is missing: libproot.so` 问题。
- **首页控制台地址与运行状态更稳定**：Dashboard URL 解析现在会自动清理误拼接到 token 后面的 `copy`、`copied`、`GatewayWS` 等噪声后缀；从 Web 控制台返回首页后会主动重新同步网关状态，尽量避免“实际仍在运行但首页显示已停止”的错位情况。
- **OpenClaw 版本切换增加进度百分比**：首页切换 OpenClaw 版本时，安装进度条旁会实时显示百分比，长时间安装时反馈更直观。
- **关键配置支持自动应用**：修改模型提供商、消息平台等关键配置后，如果网关当前正在运行，应用会自动重启网关以应用新配置，并在日志中明确记录应用过程；若网关未运行，则会提示下次启动生效。
- **版本元数据同步到正式版 1.9.6**：应用内版本号、CLI 版本号、发布产物命名与本次发布目录统一收口到 `v1.9.6`，并将 Android 构建号递增到 `39`，便于从测试包平滑覆盖安装。
## v1.9.5 鈥?蹇収瀵煎嚭閫変綅缃笌鏅鸿氨 AI 閫傞厤

### 鍏抽敭鏀瑰姩

- **蹇収瀵煎嚭鏀逛负绯荤粺淇濆瓨闈㈡澘**锛氳缃〉瀵煎嚭蹇収鏃朵笉鍐嶅浐瀹氬啓鍏ュ簲鐢ㄧ鏈夌洰褰曟垨 `Download`锛岃€屾槸鐩存帴璋冪敤 Android 绯荤粺鈥滃垱寤烘枃妗ｂ€濋潰鏉匡紝鐢辩敤鎴疯嚜宸遍€夋嫨淇濆瓨浣嶇疆涓庢枃浠跺悕锛屽浠芥枃浠舵洿瀹规槗绠＄悊鍜屾煡鎵俱€?- **鍘熺敓妗ユ帴琛ラ綈瀵煎嚭閾捐矾**锛欰ndroid 鍘熺敓渚ф柊澧炲揩鐓т繚瀛橀€氶亾锛岃兘澶熸妸搴旂敤鍐呯敓鎴愮殑閰嶇疆蹇収鐩存帴鍐欏叆鐢ㄦ埛鍦ㄧ郴缁熸枃浠堕€夋嫨鍣ㄩ噷鎸囧畾鐨勪綅缃紝骞舵纭繑鍥炴渶缁堟枃浠跺悕銆?- **鏅鸿氨 AI 鐙珛鎻愪緵鍟嗛€傞厤**锛欰I 鎻愪緵鍟嗗垪琛ㄦ柊澧?`鏅鸿氨 AI`锛屽唴缃畼鏂瑰熀纭€鍦板潃 `https://open.bigmodel.cn/api/paas/v4` 鍜屽父鐢?`GLM` 妯″瀷棰勮锛岄伩鍏嶅湪鑷畾涔夋彁渚涘晢閲岃閿欒琛ユ垚 `/v1` 瀵艰嚧璇锋眰澶辫触銆?- **鑷畾涔夋彁渚涘晢鍏煎妫€娴嬪寮?*锛氳嚜瀹氫箟妯″瀷鎻愪緵鍟嗘柊澧?`鏅鸿氨 AI Compatible` 鍏煎妯″紡锛涜繛鎺ユ祴璇曘€佽嚜鍔ㄨ瘑鍒€佸凡淇濆瓨閰嶇疆鎭㈠鍜岄璁鹃粯璁ゅ湴鍧€閫昏緫閮藉悓姝ラ€傞厤 `bigmodel.cn`锛屽苟琛ュ厖浜嗗搴旀祴璇曡鐩栥€?- **澶氳瑷€鏂囨鍚屾**锛氱畝涓€佺箒涓€佽嫳鏂囥€佹棩鏂囩殑鏅鸿氨涓庡揩鐓х浉鍏虫彁绀烘枃妗堝凡鍚屾鏇存柊锛屼繚鎸佷笉鍚岃瑷€鐣岄潰涓嬬殑閰嶇疆浣撻獙涓€鑷淬€?
## v1.9.4 鈥?棣栭〉鎺у埗鍙?Token URL 鍙岄噸淇濋櫓

### 鍏抽敭鏀瑰姩

- **棣栭〉鎺у埗鍙板湴鍧€琛ュ叏鏇寸ǔ**锛氫慨澶嶉儴鍒嗚澶囧湪瀹夎瀹屾垚鎴栫綉鍏抽噸鍚悗锛岄椤?URL 鍙樉绀?`http://127.0.0.1:18789`銆佹病鏈夎嚜鍔ㄥ甫涓?`#token=` 鐨勯棶棰樸€傜幇鍦ㄩ椤典細浼樺厛浠庢棩蹇楁彁鍙?token URL锛屽苟鍦ㄧ己澶辨椂涓诲姩鍚戠綉鍏虫帰娴嬭ˉ鍏ㄣ€?- **鏃ュ織鎶撳彇鍏煎鎬у寮?*锛氫笉鍐嶅彧渚濊禆 `localhost` / `127.0.0.1` 鐨勫浐瀹氭牸寮忥紝鑰屾槸缁熶竴瑙ｆ瀽涓嶅悓 host銆乹uery / fragment token 褰㈠紡锛屼互鍙婇儴鍒嗗搷搴斾綋涓殑 token 淇℃伅锛岄檷浣庝笂娓歌緭鍑烘牸寮忓彉鍖栧甫鏉ョ殑褰卞搷銆?- **鍚姩鏃跺簭闄嶄綆婕忔姄姒傜巼**锛氬惎鍔ㄧ綉鍏虫椂鏀逛负鍏堣闃呮棩蹇椼€佸啀鎷夎捣缃戝叧杩涚▼锛屽噺灏戝洜涓烘棩蹇楄闃呮櫄浜?token 杈撳嚭鑰岄敊杩囬鏉℃帶鍒跺彴鍦板潃鐨勬儏鍐点€?- **Node 渚?token 璇诲彇缁熶竴**锛歂ode 杩炴帴缃戝叧鏃惰鍙栨帶鍒跺彴 token 鐨勯€昏緫涔熷垏鍒扮粺涓€瑙ｆ瀽鍣紝閬垮厤棣栭〉鎷垮埌 token銆丯ode 渚у嵈鍥犳棫姝ｅ垯杩囦弗鍐嶆鍙栦笉鍒扮殑鎯呭喌銆?- **CLI 鐗堟湰鍙峰悓姝?*锛氬悓姝ヤ慨姝?`lib/index.js` 涓惤鍚庣殑 CLI 鐗堟湰鍙凤紝閬垮厤浠撳簱鍙戝竷鐗堟湰涓?CLI 杈撳嚭鐗堟湰涓嶄竴鑷淬€?
## v1.9.3 鈥?搴旂敤鍐呮洿鏂板畨瑁呮潈闄愬紩瀵间慨澶?
### 鍏抽敭鏀瑰姩

- **搴旂敤鍐呮洿鏂板畨瑁呴摼璺慨澶?*锛氫慨澶嶆洿鏂板寘涓嬭浇瀹屾垚鍚庣洿鎺ヨ烦鍥炴祻瑙堝櫒涓嬭浇椤电殑闂銆傜幇鍦ㄥ簲鐢ㄤ細浼樺厛灏濊瘯璋冪敤 Android 绯荤粺瀹夎鍣紝鑰屼笉鏄妸宸茬粡涓嬭浇濂界殑 APK 閲嶆柊浜ょ粰娴忚鍣ㄥ鐞嗐€?- **鏈煡鏉ユ簮瀹夎鏉冮檺寮曞琛ュ叏**锛氬綋璁惧灏氭湭鍏佽 OpenClaw 瀹夎鏈煡搴旂敤鏃讹紝搴旂敤浼氫富鍔ㄦ媺璧风郴缁熸巿鏉冮〉锛涙巿鏉冭繑鍥炲悗浼氱户缁墽琛屽畨瑁呮祦绋嬶紝涓嶉渶瑕佺敤鎴锋墜鍔ㄩ噸鏂版煡鎵惧畨瑁呭寘銆?- **澶辫触鍥為€€鏇村噯纭?*锛欶lutter 渚х幇鍦ㄤ細鍖哄垎鈥滄湭鎺堜簣瀹夎鏉冮檺鈥濆拰鈥滅湡姝ｅ畨瑁呭け璐モ€濅袱绉嶆儏鍐点€傚彧鏈夊湪搴旂敤鍐呯‘瀹炴棤娉曠户缁畨瑁呮椂锛屾墠浼氬洖閫€鍒版祻瑙堝櫒涓嬭浇椤碉紝骞剁粰鍑烘洿鏄庣‘鐨勬彁绀恒€?- **澶氳瑷€鎻愮ず鍚屾**锛氬悓姝ヨˉ鍏呯畝浣撲腑鏂囥€佺箒浣撲腑鏂囥€佽嫳鏂囥€佹棩鏂囩殑瀹夎澶辫触鎻愮ず鏂囨锛岄伩鍏嶄笉鍚岃瑷€鐣岄潰涓嬬殑鏇存柊鍙嶉涓嶄竴鑷淬€?
## v1.9.2 鈥?棣栭〉鏇存柊鎻愰啋鎸夐挳涓庣粺涓€鏇存柊鍏ュ彛

### 鍏抽敭鏀瑰姩

- **棣栭〉鏇存柊鎻愰啋鏇寸洿瑙?*锛氬湪棣栭〉宸︿笂瑙?`OpenClaw` 鏍囬鍙充晶鏂板杞婚噺鍖栫殑妫€鏌ユ洿鏂版寜閽紝榛樿淇濇寔浣庡瓨鍦ㄦ劅锛涘綋妫€娴嬪埌鏂扮増鏈椂锛屼細鍒囨崲鎴愭洿鏄庢樉鐨勬洿鏂板浘鏍囧苟闄勫甫绾㈢偣鎻愮ず锛屾柟渚跨涓€鏃堕棿娉ㄦ剰鍒板彲鍗囩骇鐘舵€併€?- **闈欓粯鍒锋柊鏇存柊鐘舵€?*锛氶椤典細鍦ㄩ娆¤繘鍏ャ€佸簲鐢ㄥ洖鍒板墠鍙帮紝浠ュ強浠庤缃瓑椤甸潰杩斿洖鍚庨潤榛樺埛鏂扮増鏈姸鎬侊紝涓嶉渶瑕佸弽澶嶆墜鍔ㄨ繘鍏ヨ缃〉鎵嶈兘鐭ラ亾鏄惁鏈夋柊鐗堟湰銆?- **鏇存柊娴佺▼鍏ュ彛缁熶竴**锛氶椤垫爣棰樻寜閽拰璁剧疆椤碘€滄鏌ユ洿鏂扳€濈幇鍦ㄥ鐢ㄥ悓涓€濂楀脊绐椼€佷笅杞姐€佸畨瑁呬笌澶辫触鍥為€€閫昏緫锛岄伩鍏嶄袱涓叆鍙ｈ涓轰笉涓€鑷淬€?
## v1.9.1 鈥?QQ / 寰俊鎺ュ叆涓庡簲鐢ㄥ唴鏇存柊瀹夎

### 鍏抽敭鏀瑰姩

- **QQ 鏈哄櫒浜烘帴鍏?*锛氭秷鎭钩鍙伴〉鏂板 QQ 鏈哄櫒浜哄叆鍙ｃ€傝繘鍏ラ〉闈㈡椂浼氳嚜鍔ㄦ娴嬪苟瀹夎 `@tencent-connect/openclaw-qqbot@latest` 鎻掍欢锛屽彲鐩存帴鎵撳紑鑵捐 QQ Bot 鎺ュ叆椤碉紱淇濆瓨鏃朵細鎵ц `openclaw channels add --channel qqbot --token "<AppID>:<AppSecret>"` 瀹屾垚缁戝畾锛屽苟鍦ㄥ畬鎴愬悗鎻愮ず閲嶅惎缃戝叧銆?- **寰俊鎺ュ叆寮曞**锛氭柊澧炲井淇℃帴鍏ュ叆鍙ｄ笌鐙珛瀹夎缁堢椤碉紝鍙娴?`@tencent/openclaw-weixin` 鎻掍欢鐘舵€侊紱鏈畨瑁呮椂鍙竴閿惎鍔?`npx -y @tencent-weixin/openclaw-weixin-cli install`锛屽湪缁堢涓煡鐪嬩簩缁寸爜鎴栫櫥褰曢摼鎺ュ畬鎴愮粦瀹氾紝涔熸敮鎸侀噸鏂版墦寮€缁堢缁х画澶勭悊銆?- **搴旂敤鍐呮洿鏂颁笅杞戒笌瀹夎**锛氭鏌ユ洿鏂扮幇鍦ㄤ細瑙ｆ瀽 GitHub Release 鐨勫叏閮ㄨ祫浜э紝鏍规嵁璁惧鏋舵瀯鑷姩浼樺厛閫夋嫨瀵瑰簲 APK锛屽簲鐢ㄥ唴瀹屾垚涓嬭浇鍚庣洿鎺ヨ皟鐢?Android 绯荤粺瀹夎鍣紱濡傛灉涓嬭浇鎴栧畨瑁呭け璐ワ紝浼氳嚜鍔ㄥ洖閫€鍒版祻瑙堝櫒鎵撳紑瀵瑰簲涓嬭浇椤点€?- **Android 瀹夎妗ユ帴瀹屽杽**锛氭柊澧?`FileProvider` 鍜屽畨瑁呭寘璋冪敤閫氶亾锛岃ˉ鍏?`REQUEST_INSTALL_PACKAGES` 鏉冮檺锛屽苟涓?ABI 璧勪骇閫夋嫨澧炲姞娴嬭瘯瑕嗙洊锛屾彁鍗囨洿鏂伴摼璺ǔ瀹氭€с€?
## v1.9.0 鈥?鑷畾涔夊吋瀹规彁渚涘晢銆丄PI 妫€娴嬩笌瀹夎寮曞鏉冮檺淇

### 鍏抽敭鏀瑰姩

- **鑷畾涔夊吋瀹规彁渚涘晢鎵╁睍**锛氭柊澧炵嫭绔嬬殑鑷畾涔夋彁渚涘晢璇︽儏椤碉紝鍙繚瀛樺涓嚜瀹氫箟棰勮锛屽苟鏀寔 OpenAI Chat Completions銆丱penAI Responses銆丄nthropic Messages銆丟oogle Generative AI 鍥涚被鍏煎妯″紡浠ュ強鑷姩璇嗗埆锛岄€傚悎鎺ュ叆鏇村绗笁鏂规ā鍨嬬綉鍏炽€?- **淇濆瓨鍓嶈繛鎺ユ娴?*锛氳嚜瀹氫箟鎻愪緵鍟嗘柊澧炩€滄祴璇曡繛鎺モ€濊兘鍔涳紱淇濆瓨鏃朵細浼樺厛澶嶇敤鏈€杩戜竴娆℃娴嬬粨鏋滐紝鑻ュ皻鏈娴嬫垨妫€娴嬪け璐ワ紝浼氬厛涓诲姩鎺㈡祴 API 鏄惁鍙敤锛屽苟鍦ㄥけ璐ユ椂灞曠ず鍘熷洜锛屽啀鐢辩敤鎴风‘璁ゆ槸鍚︾户缁繚瀛樸€?- **棣栭〉鐗堟湰鐘舵€佹彁绀烘洿娓呮櫚**锛氱綉鍏冲崱鐗囩殑鐗堟湰鍖哄煙鏀逛负鍥寸粫宸查€夌増鏈睍绀猴紝鏈€鏂扮増鍙綔涓哄€欓€夌増鏈彁绀猴紱褰撴娴嬪埌鏂扮増鏈椂锛屼細鏇存槑纭湴鏄剧ず鈥滃彲鏇存柊鈥濓紝鍑忓皯鈥滃綋鍓嶆渶鏂扳€濊〃杩板甫鏉ョ殑璇銆?- **瀹夎寮曞瀵煎叆蹇収鏇村厠鍒?*锛氶娆″畨瑁呭畬鎴愰〉浠嶅彲鐩存帴瀵煎叆蹇収鎭㈠閰嶇疆锛屼絾瀹夎寮曞鍦烘櫙涓嬫仮澶嶅揩鐓ф椂涓嶅啀鑷姩閲嶆柊鍚敤 Node锛岄伩鍏嶅洜涓烘棫蹇収涓殑 `nodeEnabled` 閰嶇疆瑙﹀彂鐩告満銆佸畾浣嶃€佷紶鎰熷櫒銆佽摑鐗欑瓑鏁村鏉冮檺鐢宠銆?- **浠撳簱鍙戝竷鍏冩暟鎹悓姝?*锛氬簲鐢ㄥ唴浣滆€呬俊鎭€丟itHub 閾炬帴銆佺増鏈鏌ユ帴鍙ｄ笌 CLI 鐗堟湰鍙峰凡缁忕粺涓€瀵归綈鍒版湰浠撳簱鐨?1.9.0 鍙戝竷閾捐矾锛屽悗缁彂甯冧笌鏇存柊鎻愮ず浼氭洿涓€鑷淬€?
## v1.8.9 鈥?鍙€?OpenClaw 鐗堟湰銆佸揩鐓ф仮澶嶆彁閫熶笌缃戝叧鏃ュ織杞浆

### 鍏抽敭鏀瑰姩

- **OpenClaw 鐗堟湰閫夋嫨**锛氬畨瑁呴椤典笌棣栭〉缃戝叧鍗＄墖閮芥敮鎸佹媺鍙?npm 宸插彂甯冪殑 `openclaw` 鐗堟湰鍒楄〃锛岄粯璁ら€変腑鏈€鏂扮増鏈紝涔熷彲浠ユ墜鍔ㄩ€夋嫨鎸囧畾鐗堟湰鎵ц瀹夎銆侀噸瑁呫€佸崌绾ф垨闄嶇骇锛屾柟渚垮湪涓婃父鏌愪釜鏈€鏂扮増涓存椂寮傚父鏃跺揩閫熷垏鎹€?- **鐗堟湰瀹夎閾捐矾澧炲己**锛氶€夋嫨鍏蜂綋 OpenClaw 鐗堟湰鏃讹紝浼氬悓姝ュ睍绀哄搴旂殑棰勮瀹夎浣撶Н涓?Node.js 瑕佹眰锛涘畨瑁呮祦绋嬪拰棣栭〉鎵嬪姩瀹夎閮戒細鍏堟牎楠屽唴缃?Node.js 鐗堟湰锛屼笉婊¤冻瑕佹眰鏃惰嚜鍔ㄥ崌绾у悗鍐嶇户缁€?- **蹇収鎭㈠鏇撮『鎵?*锛氬揩鐓у鍏ユ敼涓?Android 鏂囦欢閫夋嫨鍣紝涓嶅啀渚濊禆鎵嬪姩濉啓璺緞锛涘畨瑁呭畬鎴愰〉鏂板鈥滃鍏ュ揩鐓р€濇寜閽紝鍙湪涓嶉噸鏂伴厤缃?API Key 鐨勬儏鍐典笅鏇村揩鎭㈠宸叉湁閰嶇疆銆?- **蹇収瀵煎嚭浣撻獙浼樺寲**锛氬鍑哄揩鐓ф椂鏀寔鍏堣緭鍏ユ枃浠跺悕鍐嶄繚瀛橈紝渚夸簬鎸夌敤閫旀垨璁惧鎵嬪姩鍛藉悕澶囦唤鏂囦欢銆?- **缃戝叧鏃ュ織鎸佷箙鍖栦笌杞浆**锛氳缃〉鏂板鍙€夌殑缃戝叧鏃ュ織鎸佷箙鍖栧紑鍏筹紱鍚敤鍚庝細鍐欏叆 `/root/openclaw.log`锛屽崟鏂囦欢瓒呰繃 5 MB 鑷姩杞浆涓哄巻鍙叉枃浠讹紝鏈€澶氫繚鐣?3 浠姐€?- **棣栭〉淇℃伅缁嗚妭璋冩暣**锛氶椤电綉鍏冲崱鐗囦繚鐣欏綋鍓嶆ā鍨嬪睍绀猴紝骞跺鐗堟湰/鏇存柊鍖哄煙鐨勫瓧鍙蜂笌闂磋窛鍋氫簡鏀剁揣锛屼俊鎭瘑搴︽洿楂橈紝绉诲姩绔煡鐪嬫洿娓呮櫚銆?
## v1.8.8 鈥?浠〃鐩樺寮恒€侀厤缃紪杈戝櫒涓?OpenClaw 鏇存柊閾捐矾

### 鍏抽敭鏀瑰姩

- **棣栭〉蹇嵎鎿嶄綔閲嶆瀯**锛氶殣钘忊€滃紩瀵奸厤缃€濆拰鈥淲eb 鎺у埗鍙扳€濆崱鐗囷紝鏂板鈥滀慨鏀归厤缃枃浠垛€濆拰鈥滃父鐢ㄥ懡浠も€濆叆鍙ｏ紱缃戝叧鍖哄煙鏂板褰撳墠 OpenClaw 鐗堟湰鏄剧ず锛岄椤典俊鎭洿闆嗕腑銆?- **OpenClaw 鐗堟湰妫€娴嬩笌涓€閿洿鏂?*锛氱綉鍏冲崱鐗囨柊澧炩€滄鏌ユ洿鏂?/ 鏇存柊 / 鏈€鏂扳€濈姸鎬佹寜閽紱浼氬厛鏌ヨ npm 鏈€鏂?`openclaw` 鐗堟湰锛屽啀鑷姩妫€娴?Node.js 鐗堟湰瑕佹眰锛屼笉婊¤冻鏃跺厛鍗囩骇鍐呯疆 Node.js锛屽啀鎵ц `openclaw@latest` 瀹夎銆?- **閰嶇疆鏂囦欢缂栬緫鍣?*锛氭柊澧炲唴缃?`openclaw.json` 缂栬緫椤碉紝鏀寔 JSON 鏍￠獙銆佹牸寮忓寲銆佷繚瀛橈紝骞跺姞鍏?JSON 璇硶楂樹寒锛屼究浜庣洿鎺ュ尯鍒嗛敭銆佸€笺€佸竷灏斿€煎拰鏁板瓧銆?- **甯哥敤鍛戒护鍏ュ彛**锛氭柊澧炲父鐢ㄥ懡浠ら〉锛屽唴缃?`openclaw onboard --install-daemon`銆乣openclaw config set tools.profile full`銆乣openclaw configure` 涓夋潯鍛戒护锛屽苟鏀寔涓€閿鍒躲€?- **鏃ュ織澧炲己**锛氭棩蹇楅〉鐜板湪鍙垏鎹㈡煡鐪嬧€滅綉鍏虫棩蹇椻€濆拰鈥滃璇濇棩蹇椻€濓紱瀵硅瘽鏃ュ織浼氳鍙?`/root/.openclaw/agents/main/sessions/` 涓嬫渶鏂扮殑 `.jsonl` 浼氳瘽鏂囦欢銆?- **缃戝叧鍚姩 / 鍋滄鍙潬鎬?*锛氭柊澧炩€滃惎鍔ㄤ腑 / 鍋滄涓€濈姸鎬佸睍绀猴紱鍋滄缃戝叧鏃朵細涓诲姩娓呯悊娈嬬暀杩涚▼锛岄伩鍏嶅啀娆″惎鍔ㄦ椂璇姤鈥滃凡鍦ㄨ繍琛屸€濄€?- **鑷畾涔夋彁渚涘晢閰嶇疆淇**锛氬啓鍏ヨ嚜瀹氫箟鎻愪緵鍟嗛厤缃椂浼氳嚜鍔ㄨˉ榻?`gateway.mode=local`锛屼慨澶嶅洜妯″紡鏈缃鑷寸綉鍏冲惎鍔ㄨ闃绘鐨勯棶棰樸€?- **瀹夎鍚戝涓庣増鏈粏鑺備紭鍖?*锛氬畨瑁呴〉澧炲姞 OpenClaw 棰勮瀹夎澶у皬鏄剧ず锛屼綔鑰呬俊鎭粺涓€涓?`JunWan`锛涘畨瑁呬笌鏇存柊榛樿浣跨敤 `openclaw@latest`锛屽苟鍚屾灏嗛粯璁?Node.js 鐗堟湰鎻愬崌鍒?`22.16.0` 浠ユ弧瓒冲綋鍓嶄笂娓歌姹傘€?- **绉诲姩绔?Web 椤甸潰鏌ョ湅浼樺寲**锛氬簲鐢ㄥ唴鎵撳紑缃戝叧鍦板潃鏃讹紝榛樿浠ユ洿閫傚悎鎵嬫満鏌ョ湅鐨勭缉鏀炬柟寮忓睍绀?OpenClaw Web 椤甸潰銆?
## v1.8.7 鈥?鑷畾涔?OpenAI銆佹棩蹇椾紭鍖栦笌椋炰功娑堟伅骞冲彴

### 鍏抽敭鏀瑰姩

- **鑷畾涔?OpenAI 鍏煎鎻愪緵鍟?*锛欰I 鎻愪緵鍟嗛〉鏂板鈥滆嚜瀹氫箟 OpenAI 鍏煎鈥濆叆鍙ｏ紝鍙～鍐?API 鍩虹鍦板潃銆丄PI Key 鍜屼换鎰忔ā鍨嬪悕锛涘熀纭€鍦板潃浼氳嚜鍔ㄨˉ鍏ㄥ埌 `/v1`锛屾柟渚挎帴鍏ュ悇绫?OpenAI-Compatible 鏈嶅姟銆?- **缃戝叧鏃ュ織鍙鎬т紭鍖?*锛氬簲鐢ㄥ唴鏃ュ織缁熶竴娓呯悊 ANSI 棰滆壊杞箟搴忓垪锛屽苟鏍煎紡鍖栦负 `YYYY-MM-DD HH:mm:ss` 鏃堕棿鎴筹紱鍚屾椂鍑忓皯閮ㄥ垎 Android 鍦烘櫙涓?`can't sanitize binding "/proc/self/fd/*"` 杩欑被 PRoot warning 鐨勫共鎵般€?- **蹇嵎鎿嶄綔閲嶆帓**锛氫华琛ㄧ洏灏嗏€淎I 鎻愪緵鍟嗏€濈Щ鍔ㄥ埌蹇嵎鎿嶄綔棣栦綅锛屼究浜庨娆￠厤缃紱骞舵柊澧炩€滄帴鍏ユ秷鎭钩鍙扳€濆叆鍙ｏ紝鎻愬崌閰嶇疆璺緞鐨勪竴鑷存€с€?- **娑堟伅骞冲彴鎺ュ叆椤?*锛氭柊澧炩€滄帴鍏ユ秷鎭钩鍙扳€濋〉闈紝骞舵彁渚涢涓涔?/ Feishu 閰嶇疆鍏ュ彛锛岀晫闈㈤鏍间笌 AI 鎻愪緵鍟嗛〉淇濇寔涓€鑷淬€?- **椋炰功瀹樻柟閰嶇疆缁撴瀯閫傞厤**锛氶涔﹂厤缃幇鎸夊畼鏂?`channels.feishu.defaultAccount + accounts.default` 缁撴瀯鍐欏叆 `openclaw.json`锛涚綉鍏冲惎鍔ㄥ墠浼氳嚜鍔ㄨ縼绉绘棫鐨勯敊璇?`channels.lark` 閰嶇疆锛岄伩鍏嶅洜 schema 涓嶅吋瀹瑰鑷村惎鍔ㄥけ璐ャ€?
## v1.8.6 鈥?瀹夎杩涘害銆佹棩蹇楀伐鍏蜂笌鍙戝竷鑴氭湰

### 鍏抽敭鏀瑰姩

- **瀹夎杩涘害鍙嶉**锛氫紭鍖栧畨瑁呭悜瀵肩殑杩涘害鏄剧ず銆俁ootFS 瑙ｅ帇銆佸熀纭€鍖呭畨瑁呫€丯ode.js 澶勭悊鍜?OpenClaw 瀹夎绛夐暱鑰楁椂闃舵鐜板湪浼氭樉绀烘洿骞虫粦鐨勬楠ょ櫨鍒嗘瘮锛屽噺灏戦暱鏃堕棿鐪嬭捣鏉モ€滃崱浣忎笉鍔ㄢ€濈殑鎯呭喌锛涗复鏃跺姞鍏ョ殑鎬昏繘搴﹀崱鐗囦篃宸茬Щ闄わ紝浠呬繚鐣欐瘡涓楠よ嚜宸辩殑鐧惧垎姣旀樉绀恒€?- **缃戝叧鏃ュ織宸ュ叿**锛氭棩蹇楁煡鐪嬮〉鏂板鈥滄竻绌烘棩蹇椻€濇寜閽紝骞跺甫纭寮圭獥锛涜鎿嶄綔鍙細娓呯┖搴旂敤鍐呯殑鏃ュ織鍒楄〃锛屼笉浼氬垹闄ょ鐩樹笂鐨勬棩蹇楁枃浠躲€?- **鑺傜偣 WebSocket 蹇冭烦淇**锛氳妭鐐?WebSocket 蹇冭烦浠庡彂閫佹枃鏈?`ping` 鏀逛负浣跨敤搴曞眰 ping 甯э紝閬垮厤缃戝叧鍑虹幇 `Unexpected token 'p', "ping" is not valid JSON` 杩欑被 JSON 瑙ｆ瀽閿欒銆?- **PRoot 鍚姩璀﹀憡鏀舵暃**锛氱幇鍦ㄥ彧鏈夊湪瀹夸富绔爣鍑嗚緭鍏ヨ緭鍑哄彞鏌勭‘瀹炲彲缁戝畾鏃讹紝鎵嶄細缁戝畾 `/proc/self/fd/0/1/2`锛屼粠鑰屽噺灏戦儴鍒?Android 鍓嶅彴鏈嶅姟鍦烘櫙涓嬬綉鍏冲惎鍔ㄦ椂鐨?`can't sanitize binding "/proc/self/fd/*"` warning銆?- **鍙戝竷鎵撳寘娴佺▼**锛氭柊澧?`scripts/build_release.py` 鍙戝竷鏋勫缓鑴氭湰锛屽彲浜や簰杈撳叆鍙戝竷鐗堟湰鍜屾瀯寤哄彿锛岄粯璁ゅ皢鏋勫缓鍙疯涓哄綋鍓?`pubspec` 鐨勪笅涓€涓€硷紝骞跺彲鑷姩鍑嗗 PRoot 浜岃繘鍒躲€佹暣鐞?APK/AAB 鍒?`release/v鐗堟湰/` 鐩綍锛汻EADME 涔熷凡琛ュ厖瀵瑰簲璇存槑銆?
## v1.8.5 鈥?i18n Integration / 姹夊寲鏁村悎

### Key Changes / 鍏抽敭鏀瑰姩

- **Branch Integration / 鍒嗘敮鏁村悎**: Merged translation branch `pr-68` onto latest upstream `main` in commit `65a4a8b`, so this release contains both upstream fixes and i18n updates.
- **Localization Core / 鏈湴鍖栨牳蹇?*: Added localization entrypoint and string bundles at `flutter_app/lib/l10n/app_localizations.dart`, `flutter_app/lib/l10n/app_strings_en.dart`, `flutter_app/lib/l10n/app_strings_zh_hans.dart`, `flutter_app/lib/l10n/app_strings_zh_hant.dart`, and `flutter_app/lib/l10n/app_strings_ja.dart`.
- **Locale State Management / 璇█鐘舵€佺鐞?*: Added persistent locale provider `flutter_app/lib/providers/locale_provider.dart`; app language can be switched and remembered across restarts.
- **UI Coverage Expansion / 鐣岄潰瑕嗙洊鎵╁睍**: Localized major screens including dashboard, settings, setup wizard, providers, logs, onboarding, and packages in `flutter_app/lib/screens/*`.
- **Provider Metadata Updates / Provider 鍏冩暟鎹洿鏂?*: Updated provider model metadata and provider configuration flow in `flutter_app/lib/models/ai_provider.dart` and `flutter_app/lib/services/provider_config_service.dart`, including localized provider-related labels.
- **App Wiring / 搴旂敤鎺ョ嚎**: Updated app bootstrap wiring in `flutter_app/lib/app.dart` and settings/preferences handling in `flutter_app/lib/services/preferences_service.dart` to ensure locale initialization and usage is consistent.
- **Tooling / 宸ュ叿鑴氭湰**: Added helper script `flutter_app/scripts/_expand_l10n.dart` for localization text processing workflow.

## v1.8.4 鈥?Serial, Log Timestamps & ADB Backup

### New Features

- **Serial over Bluetooth & USB (#21)** 鈥?New `serial` node capability with 5 commands (`list`, `connect`, `disconnect`, `write`, `read`). Supports USB serial devices via `usb_serial` and BLE devices via Nordic UART Service (flutter_blue_plus). Device IDs prefixed with `usb:` or `ble:` for disambiguation
- **Gateway Log Timestamps (#54)** 鈥?All gateway log messages (both Kotlin and Dart side) now include ISO 8601 UTC timestamps for easier debugging
- **ADB Backup Support (#55)** 鈥?Added `android:allowBackup="true"` to AndroidManifest so users can back up app data via `adb backup`

### Enhancements

- **Check for Updates (#59)** 鈥?New "Check for Updates" option in Settings > About. Queries the GitHub Releases API, compares semver versions, and shows an update dialog with a download link if a newer release is available

### Bug Fixes

- **Node Capabilities Not Available to AI (#56)** 鈥?`_writeNodeAllowConfig()` silently failed when proot/node wasn't ready, causing the gateway to start with no `allowCommands`. Added direct file I/O fallback to write `openclaw.json` directly on the Android filesystem. Also fixed `node.capabilities` event to send both `commands` and `caps` fields matching the connect frame format

### Node Command Reference Update

| Capability | Commands |
|------------|----------|
| Serial | `serial.list`, `serial.connect`, `serial.disconnect`, `serial.write`, `serial.read` |

---

## v1.8.3 鈥?Multi-Instance Guard

### Bug Fixes

- **Duplicate Gateway Processes (#48)** 鈥?Services now guard against re-entry when Android re-delivers `onStartCommand` via `START_STICKY`, preventing duplicate processes, leaked wakelocks, and repeated answers to connected apps
- **Wakelock Leaks** 鈥?All 5 foreground services release any existing wakelock before acquiring a new one
- **Orphan PTY Instances** 鈥?Terminal, onboarding, configure, and package install screens now kill the previous PTY before starting a new one on retry
- **Notification ID Collisions** 鈥?SetupService and ScreenCaptureService no longer share notification IDs with other services

---

## v1.8.2 鈥?DNS Reliability, Screenshot Capture, Custom Models & Setup Detection

### Bug Fixes

- **Setup State Detection (#44)** 鈥?`openclawx onboard` no longer says setup isn't done after a successful setup. Replaced slow proot exec check with fast filesystem check for openclaw detection, with a longer-timeout fallback
- **DNS / No Internet Inside Proot (#45)** 鈥?resolv.conf is now written to both `config/resolv.conf` (bind-mount source) and `rootfs/ubuntu/etc/resolv.conf` (direct fallback) at every entry point: app start, every proot invocation, gateway start, SSH start, and all terminal screens. Survives APK updates
- **NVIDIA NIM Config Breaks Onboarding (#46)** 鈥?Provider config save now falls back to direct file write if the proot Node.js one-liner fails (e.g. due to DNS issues)

### New Features

- **Screenshot Capture** 鈥?All terminal and log screens now have a camera button to capture the current view as a PNG image saved to device storage
- **Custom Model Support (#46)** 鈥?AI Providers screen now allows entering any custom model name (e.g. `kimi-k2.5`) via a "Custom..." option in the model dropdown
- **Updated NVIDIA Models (#46)** 鈥?Added `meta/llama-3.3-70b-instruct` and `deepseek-ai/deepseek-r1` to NVIDIA NIM default models

### Reliability

- **resolv.conf at Every Entry Point** 鈥?`MainActivity.configureFlutterEngine()` ensures directories and resolv.conf exist on every app launch. `ProcessManager.ensureResolvConf()` guarantees it before every proot invocation. All Kotlin services and Dart screens have independent fallbacks writing to both paths
- **APK Update Resilience** 鈥?Directories and DNS config are recreated on engine init, so the app recovers automatically after an APK update clears filesDir

---

## v1.8.0 鈥?AI Providers, SSH Access, Ctrl Keys & Configure Menu

### New Features

- **AI Providers** 鈥?New "AI Providers" screen to configure API keys and select models for 7 providers: Anthropic, OpenAI, Google Gemini, OpenRouter, NVIDIA NIM, DeepSeek, and xAI. Writes configuration directly to `~/.openclaw/openclaw.json`
- **SSH Remote Access** 鈥?New "SSH Access" screen to start/stop an SSH server (sshd) inside proot, set the root password, and view connection info with copyable `ssh` commands. Runs as an Android foreground service for persistence
- **Configure Menu** 鈥?New "Configure" dashboard card opens `openclaw configure` in a built-in terminal for managing gateway settings
- **Clickable URLs** 鈥?Terminal and onboarding screens detect URLs at tap position (joining adjacent lines, stripping box-drawing characters) and offer Open/Copy/Cancel dialog

### Bug Fixes

- **Ctrl Key with Soft Keyboard (#37)** 鈥?Ctrl and Alt modifier state from the toolbar now applies to soft keyboard input across all terminal screens (terminal, configure, onboarding, package install). Previously only worked with toolbar buttons
- **Ctrl+Arrow/Home/End/PgUp/PgDn (#38)** 鈥?Toolbar Ctrl modifier now sends correct escape sequences for arrow keys and navigation keys (e.g. `Ctrl+Left` sends `ESC[1;5D`)
- **resolv.conf ENOENT after Update (#40)** 鈥?DNS resolution failed after app update because `resolv.conf` was missing. Now ensured on every app launch (splash screen), before every proot operation (`getProotShellConfig`), and in the gateway service init 鈥?covering reinstall, update, and normal launch

### Dashboard

- Added "AI Providers" and "SSH Access" quick action cards

---

## v1.7.3 鈥?DNS Fix, Snapshot & Version Sync

### Bug Fixes

- **DNS Breaks After a While (#34)** 鈥?`resolv.conf` is now written before every gateway start (in both the Flutter service and the Android foreground service), not just during initial setup. This prevents DNS resolution failures when Android clears the app's file cache
- **Version Mismatch (#35)** 鈥?Synced version strings across `constants.dart`, `pubspec.yaml`, `package.json`, and `lib/index.js` so they all report `1.7.3`

### New Features

- **Config Snapshot (#27)** 鈥?Added Export/Import Snapshot buttons under Settings > Maintenance. Export saves `openclaw.json` and app preferences to a JSON file; Import restores them. A "Snapshot" quick action card is also available on the dashboard
- **Storage Access** 鈥?Added Termux-style "Setup Storage" in Settings. Grants shared storage permission and bind-mounts `/sdcard` into proot, so files in `/sdcard/Download` (etc.) are accessible from inside the Ubuntu environment. Snapshots are saved to `/sdcard/Download/` when permission is granted

---

## v1.7.2 鈥?Setup Fix

### Bug Fixes

- **node-gyp Python Error** 鈥?Fixed `PlatformException(PROOT_ERROR)` during setup caused by npm's bundled node-gyp failing to find Python. Now installs `python3`, `make`, and `g++` in the rootfs so native addon compilation works properly
- **tzdata Interactive Prompt** 鈥?Fixed setup hanging on continent/timezone selection by pre-configuring timezone to UTC before installing python3
- **proot-compat Spawn Mock** 鈥?Removed `node-gyp` and `make` from the mocked side-effect command list since real build tools are now installed

---

## v1.7.1 鈥?Background Persistence & Camera Fix

> Requires Android 10+ (API 29)

### Node Background Persistence

- **Lifecycle-Aware Reconnection** 鈥?Handles both `resumed` and `paused` lifecycle states; forces connection health check on app resume since Dart timers freeze while backgrounded
- **Foreground Service Verification** 鈥?Watchdog, resume handler, and pause handler all verify the Android foreground service is still alive and restart it if killed
- **Stale Connection Recovery** 鈥?On app resume, detects if the WebSocket went stale (no data for 90s+) and forces a full reconnect instead of silently staying in "paired" state
- **Live Notification Status** 鈥?Foreground notification text updates in real-time to reflect node state (connected, connecting, reconnecting, error)

### Camera Fix

- **Immediate Camera Release** 鈥?Camera hardware is now released immediately after each snap/clip using `try/finally`, preventing "Failed to submit capture request" errors on repeated use
- **Auto-Exposure Settle** 鈥?Added 500ms settle time before snap for proper auto-exposure/focus
- **Flash Conflict Prevention** 鈥?Flash capability releases the camera when torch is turned off, so subsequent snap/clip operations don't conflict
- **Stale Controller Recovery** 鈥?Flash capability detects errored/stale controllers and recreates them instead of failing silently

---

## v1.7.0 鈥?Clean Modern UI Redesign

> Requires Android 10+ (API 29)

### UI Overhaul

- **New Color System** 鈥?Replaced default Material 3 purple with a professional black/white palette and red (#DC2626) accent, inspired by Linear/Vercel design language
- **Inter Typography** 鈥?Added Google Fonts Inter across the entire app for a clean, modern feel
- **AppColors Class** 鈥?Centralized color constants for consistent theming (dark bg, surfaces, borders, status colors)
- **Dark Mode** 鈥?Near-black backgrounds (#0A0A0A), subtle surface (#121212), bordered cards
- **Light Mode** 鈥?Clean white backgrounds, light borders (#E5E5E5), bordered cards

### Component Redesign

- **Zero-Elevation Cards** 鈥?All cards now use 1px borders with 12px radius instead of drop shadows
- **Pill Status Badges** 鈥?Gateway and Node controls show pill-shaped badges (icon + label) instead of 12px status dots
- **Monochrome Dashboard** 鈥?Removed rainbow icon colors from quick action cards; all icons use neutral muted tones
- **Uppercase Section Headers** 鈥?Settings, Node, and Setup screens use letterspaced muted grey headers
- **Red Accent Buttons** 鈥?Primary actions (Start Gateway, Enable Node, Install) use red filled buttons; destructive/secondary actions use outlined buttons
- **Terminal Toolbar** 鈥?Aligned colors to new palette; CTRL/ALT active state uses red accent; bumped border radius

### Splash Screen

- **Fade-In Animation** 鈥?800ms fade-in on launch with easeOut curve
- **App Icon Branding** 鈥?Uses ic_launcher.png instead of generic cloud icon
- **Inter Bold Wordmark** 鈥?"OpenClaw" displayed in Inter weight 800 with letter-spacing

### Polish

- **Log Colors** 鈥?INFO lines use muted grey (not red); WARN uses amber instead of orange
- **Installed Badges** 鈥?Package screens use consistent green (#22C55E) for "Installed" badges
- **Capability Icons** 鈥?Node screen capabilities use muted color instead of primary red
- **Input Focus** 鈥?Text fields highlight with red border on focus
- **Switches** 鈥?Red thumb when active, grey when inactive
- **Progress Indicators** 鈥?All use red accent color

### CI

- Removed OpenClaw Node app build from workflow (gateway-only CI now)

---

## v1.6.1 鈥?Node Capabilities & Background Resilience

> Requires Android 10+ (API 29)

### New Features

- **7 Node Capabilities (15 commands)** 鈥?Camera, Flash, Location, Screen, Sensor, Haptic, and Canvas now fully registered and exposed to the AI via WebSocket node protocol
- **Proactive Permission Requests** 鈥?Camera, location, and sensor permissions are requested upfront when the node is enabled, before the gateway sends invoke requests
- **Battery Optimization Prompt** 鈥?Automatically asks user to exempt the app from battery restrictions when enabling the node

### Background Resilience

- **WebSocket Keep-Alive** 鈥?30-second periodic ping prevents idle connection timeout
- **Connection Watchdog** 鈥?45-second timer detects dropped connections and triggers reconnect
- **Stale Connection Detection** 鈥?Forces reconnect if no data received for 90+ seconds
- **App Lifecycle Handling** 鈥?Auto-reconnects node when app returns to foreground after being backgrounded
- **Exponential Backoff** 鈥?Reconnect attempts use 350ms-8s backoff to avoid flooding

### Fixes

- **Gateway Config** 鈥?Patches `/root/.openclaw/openclaw.json` to clear `denyCommands` and set `allowCommands` for all 15 commands (previously wrote to wrong config file)
- **Location Timeout** 鈥?Added 10-second time limit to GPS fix with fallback to last known position
- **Canvas Errors** 鈥?Returns honest `NOT_IMPLEMENTED` errors instead of fake success responses
- **Node Display Name** 鈥?Renamed from "OpenClaw Termux" to "OpenClawX Node"

### Node Command Reference

| Capability | Commands |
|------------|----------|
| Camera | `camera.snap`, `camera.clip`, `camera.list` |
| Canvas | `canvas.navigate`, `canvas.eval`, `canvas.snapshot` |
| Flash | `flash.on`, `flash.off`, `flash.toggle`, `flash.status` |
| Location | `location.get` |
| Screen | `screen.record` |
| Sensor | `sensor.read`, `sensor.list` |
| Haptic | `haptic.vibrate` |

---

## v1.5.5

- Initial release with gateway management, terminal emulator, and basic node support


