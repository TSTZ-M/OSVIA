#!/usr/bin/env python3
"""生成 Shared/Localizable.xcstrings：小组件、控制中心、灵动岛按钮、快捷指令里由系统渲染的文字。
源语言 en（缺语种时回退英文），跟随系统语言。改完文案后运行本脚本即可。"""
import json, os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Shared', 'Localizable.xcstrings')
L = ['zh-Hans','zh-Hant','ja','ko','es','fr','de','pt-BR','it','ru','tr','vi','th','id','ar','hi']
T = {
"Timed out - open the app": ["已超时，请回到应用查看","已逾時，請回到 App 查看","タイムアウトしました。アプリで確認してください","시간이 초과되었습니다. 앱에서 확인하세요","Tiempo agotado: abre la app","Délai dépassé : ouvrez l’app","Zeitüberschreitung – App öffnen","Tempo esgotado: abra o app","Tempo scaduto: apri l’app","Время вышло — откройте приложение","Zaman aşımı — uygulamayı açın","Quá thời gian — hãy mở ứng dụng","หมดเวลา เปิดแอปเพื่อดู","Waktu habis — buka aplikasi","انتهت المهلة — افتح التطبيق","समय समाप्त — ऐप खोलें"],
"OSVIA Voice": ["OSVIA 语音","OSVIA 語音","OSVIA 音声","OSVIA 음성","OSVIA Voz","OSVIA Voix","OSVIA Sprache","OSVIA Voz","OSVIA Voce","OSVIA Голос","OSVIA Ses","OSVIA Giọng nói","OSVIA เสียง","OSVIA Suara","OSVIA الصوت","OSVIA आवाज़"],
"Open OSVIA and start voice input.": ["一键打开 OSVIA 并开始语音输入。","一鍵開啟 OSVIA 並開始語音輸入。","OSVIA を開いて音声入力を始めます。","OSVIA를 열고 음성 입력을 시작합니다.","Abre OSVIA y empieza a dictar.","Ouvre OSVIA et lance la saisie vocale.","Öffnet OSVIA und startet die Spracheingabe.","Abre o OSVIA e inicia a entrada de voz.","Apre OSVIA e avvia l’input vocale.","Открыть OSVIA и начать голосовой ввод.","OSVIA’yı açar ve sesli girişi başlatır.","Mở OSVIA và bắt đầu nhập bằng giọng nói.","เปิด OSVIA และเริ่มป้อนด้วยเสียง","Buka OSVIA dan mulai input suara.","افتح OSVIA وابدأ الإدخال الصوتي.","OSVIA खोलें और वॉइस इनपुट शुरू करें।"],
"OSVIA Chat": ["OSVIA 对话","OSVIA 對話","OSVIA チャット","OSVIA 대화","OSVIA Chat","OSVIA Chat","OSVIA Chat","OSVIA Chat","OSVIA Chat","OSVIA Чат","OSVIA Sohbet","OSVIA Trò chuyện","OSVIA แชท","OSVIA Obrolan","OSVIA دردشة","OSVIA चैट"],
"Open OSVIA and start a new chat.": ["一键打开 OSVIA 并开始新对话。","一鍵開啟 OSVIA 並開始新對話。","OSVIA を開いて新しいチャットを始めます。","OSVIA를 열고 새 대화를 시작합니다.","Abre OSVIA y empieza un chat nuevo.","Ouvre OSVIA et démarre une nouvelle conversation.","Öffnet OSVIA und startet einen neuen Chat.","Abre o OSVIA e inicia uma nova conversa.","Apre OSVIA e avvia una nuova chat.","Открыть OSVIA и начать новый чат.","OSVIA’yı açar ve yeni bir sohbet başlatır.","Mở OSVIA và bắt đầu cuộc trò chuyện mới.","เปิด OSVIA และเริ่มแชทใหม่","Buka OSVIA dan mulai obrolan baru.","افتح OSVIA وابدأ محادثة جديدة.","OSVIA खोलें और नई चैट शुरू करें।"],
"Chat": ["对话","對話","チャット","대화","Chat","Chat","Chat","Chat","Chat","Чат","Sohbet","Trò chuyện","แชท","Obrolan","دردشة","चैट"],
"Voice": ["语音","語音","音声","음성","Voz","Voix","Sprache","Voz","Voce","Голос","Ses","Giọng nói","เสียง","Suara","الصوت","आवाज़"],
"Mail": ["邮箱","郵件","メール","메일","Correo","Mail","Mail","E-mail","Mail","Почта","Posta","Thư","เมล","Email","البريد","मेल"],
"Tasks": ["任务","任務","タスク","작업","Tareas","Tâches","Aufgaben","Tarefas","Attività","Задачи","Görevler","Tác vụ","งาน","Tugas","المهام","कार्य"],
"Tap to start": ["点一下开始对话","點一下開始對話","タップして開始","탭하여 시작","Toca para empezar","Touchez pour commencer","Tippen zum Starten","Toque para começar","Tocca per iniziare","Нажмите, чтобы начать","Başlamak için dokunun","Chạm để bắt đầu","แตะเพื่อเริ่ม","Ketuk untuk mulai","اضغط للبدء","शुरू करने के लिए टैप करें"],
"Tap and speak": ["点一下，说出你的需求","點一下，說出你的需求","タップして話す","탭하고 말하세요","Toca y habla","Touchez et parlez","Tippen und sprechen","Toque e fale","Tocca e parla","Нажмите и говорите","Dokunun ve konuşun","Chạm và nói","แตะแล้วพูด","Ketuk lalu bicara","اضغط وتحدث","टैप करके बोलें"],
"Review your mail": ["查看并处理邮件","查看並處理郵件","メールを確認","메일 확인 및 처리","Revisa tu correo","Consultez vos mails","Mails prüfen","Veja seus e-mails","Controlla la posta","Просмотр почты","Postalarınıza göz atın","Xem và xử lý thư","ดูและจัดการอีเมล","Tinjau email Anda","راجع بريدك","अपना मेल देखें"],
"See today's tasks": ["查看今天的任务","查看今天的任務","今日のタスクを見る","오늘의 작업 보기","Ver las tareas de hoy","Voir les tâches du jour","Heutige Aufgaben ansehen","Ver as tarefas de hoje","Vedi le attività di oggi","Задачи на сегодня","Bugünkü görevleri gör","Xem tác vụ hôm nay","ดูงานวันนี้","Lihat tugas hari ini","عرض مهام اليوم","आज के कार्य देखें"],
"Ask anything": ["问点什么？","問點什麼？","何でも聞いてください","무엇이든 물어보세요","Pregunta lo que quieras","Posez une question","Frag mich etwas","Pergunte qualquer coisa","Chiedi qualsiasi cosa","Спросите что угодно","Bir şey sorun","Hỏi bất cứ điều gì","ถามอะไรก็ได้","Tanyakan apa saja","اسأل أي شيء","कुछ भी पूछें"],
"Say it": ["说出你的需求","說出你的需求","話しかける","말해 보세요","Dilo en voz alta","Dites-le","Sag es einfach","Fale","Dillo a voce","Скажите","Söyleyin","Hãy nói","พูดได้เลย","Ucapkan","قلها","बोलकर बताएं"],
"Jump into chat, voice, mail or tasks. Pick the entry for small and Lock Screen widgets.": ["一点就开始对话、语音，或直达邮箱和任务。小尺寸和锁屏可选入口。","一點就開始對話、語音，或直達郵件和任務。小尺寸和鎖定畫面可選入口。","チャット、音声、メール、タスクにすぐ移動。小サイズとロック画面では入口を選べます。","대화, 음성, 메일, 작업으로 바로 이동합니다. 작은 크기와 잠금 화면에서는 입구를 고를 수 있습니다.","Accede al chat, la voz, el correo o las tareas. En tamaño pequeño y en la pantalla de bloqueo puedes elegir el acceso.","Accédez au chat, à la voix, aux mails ou aux tâches. Choisissez l’entrée pour le petit format et l’écran verrouillé.","Direkt zu Chat, Sprache, Mail oder Aufgaben. Für kleine Widgets und den Sperrbildschirm wählbar.","Vá direto ao chat, voz, e-mail ou tarefas. Escolha a entrada nos widgets pequenos e na tela bloqueada.","Vai subito a chat, voce, posta o attività. Scegli l’accesso per i widget piccoli e la schermata di blocco.","Быстрый переход в чат, голос, почту или задачи. Для малого размера и экрана блокировки можно выбрать пункт.","Sohbet, ses, posta veya görevlere hızlıca geçin. Küçük boyut ve Kilit Ekranı için giriş seçilebilir.","Vào nhanh trò chuyện, giọng nói, thư hoặc tác vụ. Có thể chọn lối vào cho widget nhỏ và màn hình khóa.","ไปที่แชท เสียง เมล หรืองานได้ทันที เลือกทางเข้าได้สำหรับขนาดเล็กและหน้าจอล็อก","Langsung ke obrolan, suara, email, atau tugas. Pilih pintu masuk untuk widget kecil dan layar kunci.","انتقل مباشرة إلى الدردشة أو الصوت أو البريد أو المهام. يمكن اختيار المدخل للحجم الصغير وشاشة القفل.","चैट, आवाज़, मेल या कार्य पर सीधे जाएँ। छोटे आकार और लॉक स्क्रीन के लिए प्रवेश चुनें।"],
"Pause": ["暂停","暫停","一時停止","일시정지","Pausar","Pause","Pause","Pausar","Pausa","Пауза","Duraklat","Tạm dừng","หยุดชั่วคราว","Jeda","إيقاف مؤقت","रोकें"],
"Resume": ["继续","繼續","再開","계속","Reanudar","Reprendre","Fortsetzen","Continuar","Riprendi","Продолжить","Devam","Tiếp tục","ดำเนินการต่อ","Lanjutkan","استئناف","जारी रखें"],
"Stop": ["停止","停止","停止","중지","Detener","Arrêter","Stopp","Parar","Interrompi","Стоп","Durdur","Dừng","หยุด","Berhenti","إيقاف","रोकें"],
"Entry": ["入口","入口","入口","입구","Acceso","Entrée","Einstieg","Entrada","Accesso","Раздел","Giriş","Lối vào","ทางเข้า","Pintu masuk","المدخل","प्रवेश"],
"Open OSVIA": ["打开 OSVIA","開啟 OSVIA","OSVIA を開く","OSVIA 열기","Abrir OSVIA","Ouvrir OSVIA","OSVIA öffnen","Abrir o OSVIA","Apri OSVIA","Открыть OSVIA","OSVIA’yı aç","Mở OSVIA","เปิด OSVIA","Buka OSVIA","فتح OSVIA","OSVIA खोलें"],
"Choose where a tap leads": ["选择点击后进入的位置","選擇點擊後進入的位置","タップ時の移動先を選択","탭했을 때 이동할 위치 선택","Elige a dónde lleva el toque","Choisissez la destination du toucher","Ziel beim Tippen wählen","Escolha para onde o toque leva","Scegli dove porta il tocco","Выберите, куда ведёт нажатие","Dokununca nereye gidileceğini seçin","Chọn nơi mở khi chạm","เลือกปลายทางเมื่อแตะ","Pilih tujuan saat diketuk","اختر وجهة النقر","टैप करने पर कहाँ जाएँ चुनें"],
}
d = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
for k, v in T.items():
    assert len(v) == len(L), (k, len(v))
    loc = {"en": {"stringUnit": {"state": "translated", "value": k}}}
    for code, t in zip(L, v):
        loc[code] = {"stringUnit": {"state": "translated", "value": t}}
    d["strings"][k] = {"extractionState": "manual", "localizations": loc}

# 主应用里「快捷指令」动作的名称、参数、说明：源码里是中文键，补英文；其余语种先用英文（比显示中文强）
ZH_EN = {
"加入知识库":"Add to Knowledge Base","名称":"Name","内容":"Content","检索知识库":"Search Knowledge Base","查询":"Query","询问助理":"Ask Assistant","问题":"Question",
"运行脚本技能":"Run Script Skill","技能名":"Skill name","输入":"Input","N 分钟后提醒":"Remind in N Minutes","分钟":"Minutes","翻译屏幕":"Translate Screen","截屏":"Screenshot",
"识别图片文字":"Recognize Text in Image","识别图片里的文字（中文、英文、日文、韩文），在本机完成，不上传":"Recognizes text in an image (Chinese, English, Japanese, Korean) on device, nothing is uploaded",
"识别表格并导出":"Recognize Table and Export","识别图片或 PDF 里的表格，导出成 Excel 或 CSV，在本机完成，不上传":"Recognizes tables in an image or PDF and exports Excel or CSV on device, nothing is uploaded",
"图片或 PDF":"Image or PDF","格式":"Format","xlsx 或 csv，默认 xlsx":"xlsx or csv, default xlsx",
"提取网页文字":"Extract Web Text","提取网页正文，去掉广告和导航":"Extracts the main text of a web page, without ads and navigation","网址":"URL",
"压缩图片到指定大小":"Compress Image to Size","把图片压缩到不超过指定的 KB，输出 JPG":"Compresses an image to at most the given KB and outputs JPG","图片":"Image","最大体积（KB）":"Max size (KB)",
"合并为 PDF":"Merge into PDF","把多个 PDF 或图片按顺序合成一个 PDF":"Combines PDFs or images, in order, into one PDF","文件":"Files",
"背景":"Background","透明":"Transparent","白底":"White","蓝底":"Blue","红底":"Red",
"抠图换底色":"Remove Background","识别图片里的主体并去掉背景，可换成证件照常用的底色":"Finds the subject of an image and removes the background; can fill with ID-photo colors",
"图片自动打码":"Auto-Redact Image","自动给图里的手机号、身份证号、银行卡号、邮箱、车牌和人脸打马赛克，并清除拍摄位置":"Automatically pixelates phone numbers, ID numbers, bank cards, emails, plates and faces, and strips location data",
"读取二维码":"Read QR Code","读出图片里的二维码和条形码内容":"Reads the QR codes and barcodes in an image",
"转换文件格式":"Convert File Format","Word、Excel、PDF、图片、表格、音视频等互相转换，例如 pdf、docx、xlsx、jpg、png、txt、md、m4a":"Converts between Word, Excel, PDF, images, tables, audio and video, e.g. pdf, docx, xlsx, jpg, png, txt, md, m4a",
"目标格式":"Target format","如 pdf、docx、xlsx、jpg、png、txt、md、html、csv、m4a、mp4":"e.g. pdf, docx, xlsx, jpg, png, txt, md, html, csv, m4a, mp4",
"录音或视频转文字":"Transcribe Audio or Video","把录音、语音备忘录、视频里的说话转成文字（首次需要先在 App 里允许语音识别）":"Turns speech in recordings, voice memos and videos into text (allow speech recognition in the app first)",
"音频或视频":"Audio or video","语言代码":"Language code","留空=系统语言；如 zh-CN、en-US、ja-JP":"Leave empty for the system language; e.g. zh-CN, en-US, ja-JP",
"识别图片文字":"Recognize Text in Image",
}
for k, en in ZH_EN.items():
    loc = {"en": {"stringUnit": {"state": "translated", "value": en}}}
    for code in L:
        if code not in ('zh-Hans', 'zh-Hant'):
            loc[code] = {"stringUnit": {"state": "translated", "value": en}}
    d["strings"][k] = {"extractionState": "manual", "localizations": loc}
json.dump(d, open(OUT, 'w', encoding='utf8'), ensure_ascii=False, indent=2)
print('keys', len(T), len(ZH_EN))
