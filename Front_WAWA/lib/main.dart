import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle, PlatformException;
import 'package:http/http.dart' as http;
import 'package:translator/translator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart' hide PlayerState;
import 'package:audioplayers/audioplayers.dart';
import 'package:learning_app/api_service.dart';
import 'package:uuid/uuid.dart' show Uuid;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'models/attendance_model.dart';
import 'models/community_model.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:learning_app/models/learning_progress_model.dart';
import 'models/faq_model.dart';
import 'pronunciation_analysis_result.dart';
import 'package:learning_app/models/pronunciation_history_model.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:learning_app/models/user_profile.dart';
import 'package:learning_app/models/point_history_model.dart';
import 'package:learning_app/models/statistics_model.dart';
import 'package:learning_app/models/grammar_history_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:learning_app/models/study_group_model.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:learning_app/models/attendance_model.dart';
import 'package:learning_app/models/notification_model.dart' as model;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:learning_app/models/wordbook_model.dart';
import 'package:learning_app/models/user_word_model.dart';
import 'package:learning_app/models/challenge_model.dart';
import 'package:app_links/app_links.dart';

List<TextSpan> buildFeedbackSpans(String text) {
  final List<TextSpan> spans = [];
  // 정규식을 **(모든 문자)** 로 수정
  final RegExp exp = RegExp(r'\*\*(.*?)\*\*');
  int start = 0;

  for (final Match match in exp.allMatches(text)) {
    // 1. ** 앞의 일반 텍스트 추가
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
    }
    // 2. ** 사이의 텍스트를 볼드체로 추가
    spans.add(TextSpan(
      text: match.group(1),
      style: const TextStyle(fontWeight: FontWeight.bold), // 👈 볼드 스타일
    ));
    start = match.end;
  }

  // 3. ** 뒤의 나머지 텍스트 추가
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }
  return spans;
}

// 앱의 어느 곳에서든 화면 전환(Navigation)을 제어하기 위한 키
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// ApiService 인스턴스
final ApiService apiService = ApiService();

Route _createSlideRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.ease;
      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

// --- 1. 상품 정보를 담을 데이터 모델 클래스 ---
class ExchangeItem {
  final String brand;
  final String name;
  final int cost;
  final String imagePath; // 상품 이미지 경로

  const ExchangeItem({
    required this.brand,
    required this.name,
    required this.cost,
    required this.imagePath,
  });
}

// --- 2. 카테고리별 상품 목업 데이터 ---
// 실제 앱에서는 이 데이터를 서버 API를 통해 받아와야 합니다.
final Map<String, List<ExchangeItem>> categoryItems = {
  '편의점': const [
    ExchangeItem(brand: 'CU', name: '모바일상품권 5천원권', cost: 7000, imagePath: 'assets/item_cu_5000.png'),
    ExchangeItem(brand: 'CU', name: 'HK)헛개컨디션병', cost: 7000, imagePath: 'assets/item_condition.png'),
    ExchangeItem(brand: 'CU', name: '빙그레)투게더', cost: 9800, imagePath: 'assets/item_together.png'),
    ExchangeItem(brand: 'GS25', name: '비타500', cost: 1500, imagePath: 'assets/item_vita500.png'),
    ExchangeItem(brand: '세븐일레븐', name: '바나나맛우유', cost: 2000, imagePath: 'assets/item_banana_milk.png'),
  ],
  '카페/베이커리': const [
    ExchangeItem(brand: '스타벅스', name: '아메리카노 T', cost: 5740, imagePath: 'assets/item_starbucks_americano.png'),
    ExchangeItem(brand: '스타벅스', name: '카페 라떼 T', cost: 6440, imagePath: 'assets/item_starbucks_latte.png'),
    ExchangeItem(brand: '파리바게뜨', name: '1만원 금액권', cost: 12000, imagePath: 'assets/item_paris.png'),
    ExchangeItem(brand: '투썸플레이스', name: '떠먹는 스트로베리 초콜릿 생크림', cost: 8000, imagePath: 'assets/item_twosome_cake.png'),
  ],
  '이마트24': const [
    ExchangeItem(brand: '이마트24', name: '이마트24 1만원권', cost: 12000, imagePath: 'assets/item_emart_10000.png'),
    ExchangeItem(brand: '이마트24', name: '이마트24 3만원권', cost: 35000, imagePath: 'assets/item_emart_30000.png'),
  ],
  '외식': const [
    ExchangeItem(brand: 'BHC', name: '뿌링클+콜라1.25L', cost: 25000, imagePath: 'assets/item_bhc_ppuring.png'),
    ExchangeItem(brand: '도미노피자', name: '포테이토(오리지널)L+콜라1.25L', cost: 30000, imagePath: 'assets/item_domino_potato.png'),
    ExchangeItem(brand: '맘스터치', name: '싸이버거 세트', cost: 8000, imagePath: 'assets/item_momstouch_thigh.png'),
  ],
  '뷰티': const [
    ExchangeItem(brand: '올리브영', name: '기프트카드 1만원권', cost: 12000, imagePath: 'assets/item_olive_10000.png'),
    ExchangeItem(brand: '올리브영', name: '기프트카드 3만원권', cost: 12000, imagePath: 'assets/item_olive_30000.png'),
  ],
  '문화생활': const [
    ExchangeItem(brand: 'CGV', name: '일반관람권(2D)', cost: 15000, imagePath: 'assets/item_cgv_movie.png'),
    ExchangeItem(brand: '메가박스', name: '일반관람권(2D)', cost: 15000, imagePath: 'assets/item_megabox_movie.png'),
  ],
};

// 1. 데이터 모델 클래스 (수정 없음)
class WordData {
  final String word;
  final String pronunciation;
  final String definition;
  final String englishExample;
  bool isMemorized;
  bool isFavorite;

  WordData({
    required this.word,
    required this.pronunciation,
    required this.definition,
    required this.englishExample,
    this.isMemorized = false,
    this.isFavorite = false,
  });
}

// 2. 로컬 단어 목록 관리 클래스 (수정 없음)
class Dictionary {
  static final Set<String> _words = {};
  static Set<String> get words => _words;

  static Future<void> load() async {
    try {
      final fileContents = await rootBundle.loadString('assets/words_alpha.txt');
      final wordList = fileContents.split('\n');
      _words.addAll(wordList.map((word) => word.trim()).where((word) => word.isNotEmpty));
      print('기준 단어 목록 로딩 완료: 총 ${_words.length}개');
    } catch (e) {
      print('words_alpha.txt 파일 로딩 실패: $e');
    }
  }

  static bool contains(String word) {
    return _words.contains(word.toLowerCase());
  }
}

class CharacterAnimationScreen extends StatefulWidget {
  final String imagePath;
  const CharacterAnimationScreen({Key? key, required this.imagePath}) : super(key: key);

  @override
  _CharacterAnimationScreenState createState() => _CharacterAnimationScreenState();
}

class _CharacterAnimationScreenState extends State<CharacterAnimationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.1, end: 6.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            // ▼▼▼ isAdmin 값을 false로 전달합니다. ▼▼▼
            pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(isAdmin: false),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: Duration(milliseconds: 500),
          ),
              (route) => false,
        );
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 배경색은 Theme에서 관리하므로 직접 지정하지 않습니다.
      body: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Image.asset(
            widget.imagePath,
            width: 50,
            height: 50,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('userSettings');
  await _loadSentenceData();
  await Dictionary.load();
  runApp(MyApp());
}

class AppState {
  static String selectedCharacterImage = 'assets/fox.png';
  static String selectedCharacterName = '여우';

  // 기존 selectedLanguage를 역할에 맞게 targetLanguage로 이름 변경
  static String? targetLanguage;
  static String? nativeLanguage;

  static final List<WordData> favoriteWords = [];
  static final List<String> sentencePool = [];

  static String? userName;
  static String? userLevel;
  static String? userEmail;
  static String? userId;
  static Map<String, dynamic>? learningGoals;
  static ProgressStats? progressStats;
  static bool beginnerMode = false;
  static ValueNotifier<int> points = ValueNotifier(0);

  // 언어 코드('en')를 표시 이름('영어')으로 변환하기 위한 Map
  static final Map<String, String> _languageCodeToName = {
    'ko': '한국어',
    'en': '영어',
    'ja': '일본어',
    'zh': '중국어',
    'fr': '프랑스어',
    'es': '스페인어',
    'de': '독일어',
  };

  // 프로필 정보로 AppState를 업데이트하는 함수
  static void updateFromProfile(Map<String, dynamic> profileData) {
    print("🔄 [프로필 업데이트] API가 보내준 프로필 정보: $profileData");
    userName = profileData['name'];
    userLevel = profileData['assessed_level'];
    userEmail = profileData['email'];
    userId = profileData['user_id'];

    final rawGoals = profileData['learning_goals'];
    if (rawGoals is String) {
      try {
        learningGoals = jsonDecode(rawGoals) as Map<String, dynamic>?;
      } catch (e) {
        print("❌ learning_goals 문자열 파싱 실패: $e");
        learningGoals = null;
      }
    } else if (rawGoals is Map) {
      learningGoals = rawGoals as Map<String, dynamic>?;
    } else {
      learningGoals = null;
    }

    // DB에 저장된 'en', 'ko' 같은 언어 코드를 '영어', '한국어' 같은 표시 이름으로 변환하여 저장
    nativeLanguage = _languageCodeToName[profileData['native_language']];
    targetLanguage = _languageCodeToName[profileData['target_language']];

    if (profileData['selected_character_name'] != null) {
      selectedCharacterName = profileData['selected_character_name'];
    }
    if (profileData['selected_character_image'] != null) {
      selectedCharacterImage = profileData['selected_character_image'];
    }
    beginnerMode = profileData['beginner_mode'] ?? false;
    points.value = profileData['points'] ?? 0;
  }

  static Map<String, dynamic> firstLesson = {};
  static List<String> dailyGoals = [];
  static List<String> recommendations = [];
  static List<String> nextSteps = [];
}

Future<void> _loadSentenceData() async {
  try {
    // assets 폴더에 넣은 .txt 파일의 경로를 정확히 적어줍니다.
    final String fileContents = await rootBundle.loadString('assets/tatoeba_eng_50k.txt');

    // 줄바꿈(\n)을 기준으로 각 줄을 나누어 리스트에 추가합니다.
    final List<String> lines = fileContents.split('\n');
    for (var line in lines) {
      if (line.isNotEmpty) { // 비어있는 줄은 제외
        AppState.sentencePool.add(line.trim());
      }
    }
    print('✅ 문장 데이터 로드 완료: 총 ${AppState.sentencePool.length}개');
  } catch (e) {
    print('❌ 문장 데이터 로드 실패: $e');
    // 실패 시를 대비한 기본 문장 추가
    AppState.sentencePool.add("The quick brown fox jumps over the lazy dog.");
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 딥링크 처리 로직은 이제 MyApp에 있으므로 여기서는 자동 로그인 확인만 합니다.
    // 화면이 그려진 직후에 호출되도록 addPostFrameCallback 사용
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLoginStatus();
    });
  }

  // 자동 로그인 함수 (이전과 동일)
  Future<void> _checkLoginStatus() async {
    final bool autoLoginEnabled = await apiService.getAutoLoginPreference();
    if (!autoLoginEnabled) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => InitialScreen()));
      return;
    }

    // 초기 딥링크를 확인하는 로직은 MyApp으로 이동했으므로 여기서는 불필요.
    final response = await apiService.attemptAutoLogin();
    final navigator = Navigator.of(context); // mounted 체크를 위해 변수 할당

    if (response['status'] == 'ok' && mounted) {
      final userProfile = response['user_profile'];
      AppState.updateFromProfile(userProfile);

      if (userProfile['assessed_level'] == null || userProfile['assessed_level'].isEmpty) {
        navigator.pushReplacement(MaterialPageRoute(builder: (context) => const LevelTestScreen()));
      } else if (userProfile['learning_goals'] == null) {
        navigator.pushReplacement(MaterialPageRoute(builder: (context) => const GoalSettingScreen()));
      } else if (userProfile['selected_character_name'] == null || userProfile['selected_character_name'].isEmpty) {
        navigator.pushReplacement(MaterialPageRoute(builder: (context) => CharacterSelectionScreen()));
      } else if (userProfile['native_language'] == null || userProfile['target_language'] == null) {
        navigator.pushReplacement(MaterialPageRoute(builder: (context) => const LanguageSettingScreen()));
      } else {
        final bool isAdmin = userProfile['is_admin'] ?? false;
        navigator.pushReplacement(MaterialPageRoute(builder: (context) => HomeScreen(isAdmin: isAdmin)));
      }
    } else {
      await apiService.logout();
      if(mounted) {
        navigator.pushReplacement(MaterialPageRoute(builder: (context) => InitialScreen()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // 앱이 실행되는 동안 절대 파괴되지 않는 이곳에서 딥링크 리스너를 초기화합니다.
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      print('🔗 [MyApp] 딥링크 감지됨: $uri');
      _processAuthCallback(uri);
    }, onError: (err) {
      print('❌ [MyApp] 딥링크 오류: $err');
    });
  }

  // SplashScreen에 있던 콜백 처리 함수를 그대로 이곳으로 가져옵니다.
  Future<void> _processAuthCallback(Uri link) async {
    final authCode = link.queryParameters['code'];

    if (authCode != null) {
      print('🔑 [MyApp] 소셜 로그인 콜백 수신! 코드를 토큰으로 교환 시작');
      try {
        final loginResponse = await apiService.exchangeCodeForToken(authCode);
        final accessToken = loginResponse['access_token'];

        if (accessToken != null) {
          await apiService.saveToken(accessToken);
          final userProfile = await apiService.getUserProfile();
          AppState.updateFromProfile(userProfile);

          // context 대신 전역 navigatorKey를 사용하여 화면을 전환합니다.
          final navigator = navigatorKey.currentState;
          if (navigator == null) return;

          if (userProfile['assessed_level'] == null || userProfile['assessed_level'].isEmpty) {
            navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LevelTestScreen()),
                    (route) => false);
          } else if (userProfile['learning_goals'] == null) {
            navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const GoalSettingScreen()),
                    (route) => false);
          } else {
            navigator.pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (context) => HomeScreen(isAdmin: userProfile['is_admin'] ?? false)),
                    (route) => false);
          }
        } else {
          throw Exception("백엔드로부터 유효한 토큰을 받지 못했습니다.");
        }
      } catch (e) {
        print('🔥🔥🔥 [MyApp] 소셜 로그인 최종 처리 실패: $e');
        navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => LoginScreen()),
                (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ▼▼▼ [3. navigatorKey 할당] ▼▼▼
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Learning App',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'), // 한국어 지원
        Locale('en', 'US'), // 영어 지원 (선택사항)
      ],
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF3F4F8),
        fontFamily: 'Pretendard',
        primarySwatch: Colors.green,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF3F4F8),
          foregroundColor: Colors.black,
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Pretendard'),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.green, width: 1.5)),
          filled: true,
          fillColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            // minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
        checkboxTheme: CheckboxThemeData(fillColor: MaterialStateProperty.all(Colors.green)),
        tabBarTheme: const TabBarThemeData(
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.green
        ),
      ),
      home: SplashScreen(),
    );
  }
}

// 초기 화면
class InitialScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Spacer(flex: 2),
              Image.asset(
                'assets/all.png',
                width: 200,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.pets,
                      size: 100,
                      color: Colors.green,
                    ),
                  );
                },
              ),
              SizedBox(height: 60),
              Text(
                '다국어 언어 학습',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '다국어 능력 향상을 위한 앱',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                ),
              ),
              Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SignupScreen()),
                    );
                  },
                  child: Text('회원가입'),
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton( // 로그인 버튼은 OutlinedButton으로 변경하여 구분
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => LoginScreen()),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    '로그인',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// 회원가입 화면
class SignupScreen extends StatefulWidget {
  @override
  _SignupScreenState createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToAll = false; // '전체 동의' 상태
  bool _agreeToTerms = false; // '이용약관' 상태
  bool _agreeToPrivacy = false; // '개인정보 처리방침' 상태
  bool _agreeToMarketing = false; // '마케팅' 상태 (선택)

  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  // 👇 이름 검사 관련 상태 추가
  bool _isCheckingName = false;
  bool? _isNameAvailable; // null=미검사, true=사용가능, false=중복
  String? _nameMessage;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onAgreeAllChanged(bool? value) {
    if (value == null) return;
    setState(() {
      _agreeToAll = value;
      _agreeToTerms = value;
      _agreeToPrivacy = value;
      _agreeToMarketing = value; // 선택 항목도 함께 변경
    });
  }

  // 개별 체크박스가 변경될 때 '전체 동의' 상태를 업데이트하는 함수
  void _updateAgreeAllState() {
    final allChecked = _agreeToTerms && _agreeToPrivacy && _agreeToMarketing;
    setState(() {
      _agreeToAll = allChecked;
    });
  }

  // 👇 이름 입력이 변경될 때마다 호출되는 함수
  void _onNameChanged(String value) {
    _debounceTimer?.cancel();

    setState(() {
      _isNameAvailable = null;
      _nameMessage = null;
    });

    if (value.trim().length < 2) {
      setState(() {
        _nameMessage = '이름은 2자 이상이어야 합니다.';
      });
      return;
    }

    // ✅ 디버깅 로그 추가
    print('DEBUG: Starting debounce timer for: $value');

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      print('DEBUG: Timer fired, calling _checkName');
      _checkName(value);
    });
  }

  // 👇 실제 중복 검사를 수행하는 함수
  Future<void> _checkName(String name) async {
    // 사용자가 모든 입력을 지웠을 때는 검사를 멈춥니다.
    if (name.isEmpty) {
      _debounceTimer?.cancel();
      setState(() {
        _isNameAvailable = null;
        _nameMessage = null;
        _isCheckingName = false;
      });
      return;
    }

    setState(() {
      _isCheckingName = true;
      _nameMessage = '이름 확인 중...';
    });

    try {
      // 2단계에서 수정한 함수는 이제 Map<String, dynamic>을 반환합니다.
      final responseBody = await _apiService.checkNameAvailability(name);
      final isAvailable = responseBody['available'] ?? false;

      if (mounted) {
        setState(() {
          _isNameAvailable = isAvailable;
          if (isAvailable) {
            _nameMessage = '✓ 사용 가능한 이름입니다.';
          } else {
            // 성공 응답(200)이지만 available: false 인 경우 (중복된 이름)
            _nameMessage = '이미 사용 중인 이름입니다.';
          }
        });
      }
    } on ApiException catch (e) {
      // ✨ 핵심 수정: 백엔드가 보낸 구체적인 오류 메시지(예: "이름에는 공백을...")를 표시합니다.
      if (mounted) {
        setState(() {
          _isNameAvailable = false; // 오류가 발생했으므로 사용 불가능 상태로 처리
          _nameMessage = e.message; // API가 보낸 오류 메시지를 그대로 사용
        });
      }
    } catch (e) {
      // 네트워크 오류 등 기타 예외 처리
      if (mounted) {
        setState(() {
          _isNameAvailable = false;
          _nameMessage = '이름 확인 중 오류가 발생했습니다.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingName = false;
        });
      }
    }
  }

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();

    if (_emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _nameController.text.isEmpty) {
      _showErrorSnackBar('필수 항목(*)을 모두 입력해주세요.');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showErrorSnackBar('비밀번호가 일치하지 않습니다.');
      return;
    }

    // 👇 이름 중복 검사 확인
    if (_isNameAvailable != true) {
      _showErrorSnackBar('사용 가능한 이름을 입력해주세요.');
      return;
    }

    if (!_agreeToTerms || !_agreeToPrivacy) {
      _showErrorSnackBar('필수 약관에 동의해주세요.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _apiService.register(
        email: _emailController.text,
        password: _passwordController.text,
        name: _nameController.text,
      );

      if (response['access_token'] != null) {
        await _apiService.createProfile();
      }

      if (mounted) {
        final bool confirmationRequired = response['confirmation_required'] ?? false;

        if (confirmationRequired) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('가입 확인 이메일이 전송되었습니다. 메일함을 확인해주세요.'),
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('회원가입에 성공했습니다! 로그인 페이지로 이동합니다.')),
          );
          Future.delayed(const Duration(seconds: 1), () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => LoginScreen()),
            );
          });
        }
      }
    } on ApiException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('알 수 없는 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('회원가입'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(
                  label: '이메일 *',
                  controller: _emailController,
                  hint: '예) abc@gmail.com'
              ),
              const SizedBox(height: 16),
              _buildPasswordField(
                  label: '비밀번호 *',
                  controller: _passwordController,
                  isObscured: _obscurePassword,
                  onToggle: () => setState(() => _obscurePassword = !_obscurePassword)
              ),
              const SizedBox(height: 16),
              _buildPasswordField(
                  label: '비밀번호 확인 *',
                  controller: _confirmPasswordController,
                  isObscured: _obscureConfirmPassword,
                  onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword)
              ),
              const SizedBox(height: 16),

              // 👇 이름 필드를 특별한 위젯으로 변경
              _buildNameField(),

              const SizedBox(height: 24),

              const Divider(),
              _buildTermRow(
                text: '전체 동의 (선택 항목 포함)',
                isHeader: true,
                value: _agreeToAll,
                onChanged: _onAgreeAllChanged,
              ),
              const Divider(),
              _buildTermRow(
                text: '이용약관 동의 (필수)',
                value: _agreeToTerms,
                onChanged: (value) {
                  setState(() => _agreeToTerms = value!);
                  _updateAgreeAllState();
                },
                onViewDetails: () {
                  Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const PolicyViewScreen(
                        title: '이용약관',
                        content: termsOfServiceContent,
                      )
                  ));
                },
              ),
              _buildTermRow(
                text: '개인정보 처리방침 동의 (필수)',
                value: _agreeToPrivacy,
                onChanged: (value) {
                  setState(() => _agreeToPrivacy = value!);
                  _updateAgreeAllState();
                },
                onViewDetails: () {
                  Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const PolicyViewScreen(
                        title: '개인정보 처리방침',
                        content: privacyPolicyContent,
                      )
                  ));
                },
              ),
              _buildTermRow(
                text: '마케팅 정보 수신 동의 (선택)',
                value: _agreeToMarketing,
                onChanged: (value) {
                  setState(() => _agreeToMarketing = value!);
                  _updateAgreeAllState();
                },
              ),
              const SizedBox(height: 40),
              SizedBox( // '완료' 버튼
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _isLoading ? null : _handleRegister,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('완료'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 👇 이름 입력 필드 위젯 (중복 검사 기능 포함)
  Widget _buildNameField() {
    Color? borderColor;
    Color? messageColor;

    if (_isNameAvailable == true) {
      borderColor = Colors.green;
      messageColor = Colors.green;
    } else if (_isNameAvailable == false) {
      borderColor = Colors.red;
      messageColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
            '이름 *',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          onChanged: _onNameChanged,
          decoration: InputDecoration(
            hintText: '예) 홍길동',
            suffixIcon: _isCheckingName
                ? const SizedBox(
              width: 20,
              height: 20,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
                : _isNameAvailable == true
                ? const Icon(Icons.check_circle, color: Colors.green)
                : _isNameAvailable == false
                ? const Icon(Icons.cancel, color: Colors.red)
                : null,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: borderColor ?? Colors.grey.shade300,
                width: borderColor != null ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: borderColor ?? Colors.green,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (_nameMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _nameMessage!,
            style: TextStyle(
              fontSize: 12,
              color: messageColor ?? Colors.grey.shade700,
            ),
          ),
        ],
      ],
    );
  }

  // 기존 헬퍼 위젯들...
  Widget _buildTextField({required String label, required TextEditingController controller, required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        SizedBox(height: 8),
        TextField(controller: controller, decoration: InputDecoration(hintText: hint)),
      ],
    );
  }

  Widget _buildPasswordField({required String label, required TextEditingController controller, required bool isObscured, required VoidCallback onToggle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isObscured,
          decoration: InputDecoration(
            hintText: '영문, 숫자 조합 8~16자',
            suffixIcon: IconButton(
              icon: Icon(isObscured ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTermRow({
    required String text,
    required bool value,
    required ValueChanged<bool?> onChanged,
    VoidCallback? onViewDetails,
    bool isHeader = false,
  }) {
    return Row(
      children: [
        Checkbox(value: value, onChanged: onChanged),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: isHeader ? 16 : 14,
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        if (onViewDetails != null)
          TextButton(
            onPressed: onViewDetails,
            child: Text(
              '자세히보기',
              style: TextStyle(
                color: Colors.grey.shade600,
                decoration: TextDecoration.underline,
                fontSize: 12,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }
}

// 로그인 화면
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool _autoLogin = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 소셜 로그인 함수 (변경 없음)
  Future<void> _handleSocialLogin(String provider) async {
    setState(() => _isLoading = true);
    try {
      await _apiService.launchSocialLogin(provider);
    } on ApiException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('소셜 로그인 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ▼▼▼ [핵심 수정] 로그인 처리 함수 ▼▼▼
  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showErrorSnackBar('이메일과 비밀번호를 모두 입력해주세요.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _apiService.login(
        email: _emailController.text,
        password: _passwordController.text,
      );

      // --- 성공 시 화면 전환 로직 ---
      if (mounted && response['access_token'] != null) {
        final userProfile = await _apiService.getUserProfile();
        AppState.updateFromProfile(userProfile);

        if (userProfile['assessed_level'] == null || userProfile['assessed_level'].isEmpty) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LevelTestScreen()));
        } else if (userProfile['learning_goals'] == null) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const GoalSettingScreen()));
        } else if (userProfile['selected_character_name'] == null || userProfile['selected_character_name'].isEmpty) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CharacterSelectionScreen()));
        } else if (userProfile['native_language'] == null || userProfile['target_language'] == null) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LanguageSettingScreen()));
        } else {
          final bool isAdmin = userProfile['is_admin'] ?? false;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomeScreen(isAdmin: isAdmin)));
        }
      }
    } on ApiException catch (e) {
      // [핵심] 이제 ApiService가 백엔드의 구체적인 오류 메시지를 담은 ApiException을 throw하므로,
      // 여기서 e.message를 사용하면 "아이디 또는 비밀번호가 다릅니다."가 정확히 표시됩니다.
      if (mounted) {
        _showErrorSnackBar(e.message);
      }
    } catch (e) {
      // ApiException이 아닌 다른 종류의 예외 (네트워크 연결 실패 등)를 처리합니다.
      if (mounted) {
        _showErrorSnackBar('로그인 중 오류가 발생했습니다. 네트워크 연결을 확인해주세요.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 에러 메시지를 보여주는 헬퍼 함수 (변경 없음)
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // build 함수 및 소셜 로그인 버튼 위젯 (변경 없음)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const SizedBox(height: 50.0),
              const Text('로그인', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 60),
              TextField(controller: _emailController, decoration: const InputDecoration(labelText: '이메일')),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              CheckboxListTile(
                title: const Text('자동 로그인'),
                value: _autoLogin,
                onChanged: (bool? value) {
                  setState(() {
                    _autoLogin = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('로그인'),
                ),
              ),
              const SizedBox(height: 40),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('SNS 계정으로 로그인', style: TextStyle(color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: _buildSocialLoginButton(
                  provider: 'kakao',
                  label: 'Kakao로 로그인',
                  iconPath: 'assets/kakao.png',
                  backgroundColor: const Color(0xFFFEE500),
                  textColor: Colors.black,
                ),
              ),
              const SizedBox(height: 100.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialLoginButton({
    required String provider,
    required String label,
    required String iconPath,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return ElevatedButton(
      onPressed: _isLoading ? null : () => _handleSocialLogin(provider),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50), // 높이 50으로 설정
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        elevation: 1,
        side: backgroundColor == Colors.white ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(iconPath, height: 24, width: 24, errorBuilder: (c, e, s) => const Icon(Icons.login, size: 20)),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}

class TestQuestion {
  final String id;
  final String text;
  final Map<String, String> options;
  final String? passage;
  final String? audioScenario;
  final bool isFavorite; // 👈 [추가] 즐겨찾기 상태 변수

  TestQuestion({
    required this.id,
    required this.text,
    required this.options,
    this.passage,
    this.audioScenario,
    this.isFavorite = false, // 👈 [추가] 생성자에 기본값 설정
  });

  factory TestQuestion.fromJson(Map<String, dynamic> json) {
    final optionsMap = Map<String, String>.from(json['options'] ?? {});

    return TestQuestion(
      id: json['question_id'] ?? '',
      text: json['question'] ?? '질문을 불러올 수 없습니다.',
      options: optionsMap,
      passage: json['passage'] as String?,
      audioScenario: json['audio_scenario'] as String?,
      isFavorite: json['is_favorite'] ?? false, // 👈 [추가] 서버 데이터로 값 설정
    );
  }
}

// 2. API 통신 서비스 클래스
class LevelTestApiService {
  // ❗️ 중요: FastAPI 서버가 실행 중인 IP 주소로 변경하세요!
  // 예: final String _baseUrl = 'http://192.168.0.5:8000';
  final String _baseUrl = const String.fromEnvironment(
      'AI_BACKEND_URL',
      defaultValue: 'http://10.0.2.2:8000'
  ); // 로컬 테스트용 주소

  // 테스트 시작 API 호출
  Future<Map<String, dynamic>> startTest(String userId, String language) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/level-test/start'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId, 'language': language}),
    );

    if (response.statusCode == 200) {
      // 👇 [디버깅 코드] 서버가 보낸 실제 응답 내용을 확인하기 위해 이 줄을 추가하세요.
      print('서버 응답: ${utf8.decode(response.bodyBytes)}');
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('레벨 테스트를 시작하지 못했습니다.');
    }
  }

  Future<Map<String, dynamic>> startMiniVocabTest(String userId) async {
    final response = await http.post(
      // AI 서버에 새로 추가한 미니 테스트 엔드포인트 주소
      Uri.parse('$_baseUrl/api/level-test/start-mini'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId, 'language': 'english'}),
    );

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('미니 어휘력 테스트를 시작하지 못했습니다.');
    }
  }

  // 답변 제출 API 호출
  Future<Map<String, dynamic>> submitAnswer(String sessionId, String questionId, String answer) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/level-test/answer'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'session_id': sessionId,
        'question_id': questionId,
        'answer': answer,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('답변을 제출하지 못했습니다.');
    }
  }

  // 최종 결과 요청 API 호출
  Future<Map<String, dynamic>> completeAssessment(String userId, String sessionId) async {
    // 👇 [수정됨] user_id와 session_id를 URL에 직접 포함시킵니다.
    final url = Uri.parse('$_baseUrl/api/user/complete-assessment?user_id=$userId&session_id=$sessionId');

    // 디버깅을 위해 추가한 print문
    print('>>> [LevelTestApiService] 서버로 보내는 최종 URL: $url');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      // 👇 [수정됨] body 부분을 삭제하거나 주석 처리합니다.
      // body: json.encode({ ... }),
    );

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      print('### 평가 완료 오류: ${response.statusCode} - ${response.body}');
      throw Exception('결과를 불러오지 못했습니다.');
    }
  }
}

class _TestProgress {
  final TestQuestion question;
  final String? selectedAnswer;

  _TestProgress({required this.question, this.selectedAnswer});
}

// 3. 동적으로 변경된 레벨 테스트 화면
class LevelTestScreen extends StatefulWidget {
  final bool isMiniTest;

  const LevelTestScreen({Key? key, this.isMiniTest = false}) : super(key: key);

  @override
  _LevelTestScreenState createState() => _LevelTestScreenState();
}

class _LevelTestScreenState extends State<LevelTestScreen> {
  final LevelTestApiService _apiService = LevelTestApiService();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isLoading = true;
  String? _sessionId;
  TestQuestion? _currentQuestion;
  int _questionNumber = 0;
  int _totalQuestions = 0;
  String? _selectedAnswer;
  String? _errorMessage;

  final List<_TestProgress> _progressHistory = [];

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startTest();
  }

  Future<void> _speak(String text) async {
    // 언어 설정 (AppState의 선택된 언어에 따라 분기)
    String langCode = "en-US"; // 기본값 영어
    if (AppState.targetLanguage == '한국어') langCode = "ko-KR";
    if (AppState.targetLanguage == '일본어') langCode = "ja-JP";
    // 필요한 경우 다른 언어 코드 추가

    await _flutterTts.stop();
    await _flutterTts.setLanguage(langCode);
    await _flutterTts.setSpeechRate(0.5); // 재생 속도
    await _flutterTts.setVolume(1.0);   // 볼륨
    await _flutterTts.speak(text);
  }

  Future<void> _startTest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _progressHistory.clear();
    });

    try {
      final response = widget.isMiniTest
          ? await _apiService.startMiniVocabTest(AppState.userId!)
          : await _apiService.startTest(AppState.userId!, AppState.targetLanguage ?? 'english');
      print('서버 응답: ${response.toString()}');

      if (response['success'] == true) {
        final sessionId = response['session_id'];
        final currentQuestionJson = response['current_question'];

        final totalQuestions = (response['total_questions'] as num?)?.toInt() ?? (widget.isMiniTest ? 3 : 15);

        setState(() {
          _sessionId = sessionId;
          _currentQuestion = TestQuestion.fromJson(currentQuestionJson);
          _questionNumber = 1;
          _totalQuestions = totalQuestions; // 파싱한 값을 상태에 저장
          _isLoading = false;
        });

      } else {
        setState(() {
          _errorMessage = response['error']?.toString() ?? '알 수 없는 서버 오류가 발생했습니다.';
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print('### _startTest 오류: $e');
      print('### 스택 트레이스: $stackTrace'); // 더 자세한 오류 확인을 위해 추가
      setState(() {
        _errorMessage = '서버에 연결할 수 없습니다. 서버가 실행 중인지 확인해주세요.';
        _isLoading = false;
      });
    }
  }

  Future<void> _submitAndNext() async {
    if (_selectedAnswer == null || _sessionId == null || _currentQuestion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('답을 선택해주세요!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // 현재 문제가 마지막 문제인지 클라이언트 기준으로 확인
    final bool isLastQuestion = _questionNumber >= _totalQuestions;

    try {
      final response = await _apiService.submitAnswer(
        _sessionId!,
        _currentQuestion!.id,
        _selectedAnswer!,
      );

      if (response['success'] == true) {
        if (isLastQuestion) {
          // 마지막 문제(4/4)의 답을 제출했으므로, 결과 화면으로 이동
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => LevelTestResultScreen(
                sessionId: _sessionId!,
                isMiniTest: widget.isMiniTest,
              ),
            ),
          );
        } else {
          // 아직 다음 문제가 남았을 경우
          final responseData = response['data'];

          _progressHistory.add(
            _TestProgress(
              question: _currentQuestion!,
              selectedAnswer: _selectedAnswer,
            ),
          );

          // 서버가 보내준 다음 문제로 화면 업데이트
          setState(() {
            _currentQuestion = TestQuestion.fromJson(responseData['next_question']);
            _questionNumber++;
            _selectedAnswer = null;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = response['error'] ?? '답변 처리 중 오류가 발생했습니다.';
          _isLoading = false;
        });
      }
    } catch (e) {
      print("### _submitAndNext 오류: $e");
      setState(() {
        _errorMessage = '서버와 통신 중 오류가 발생했습니다.';
        _isLoading = false;
      });
    }
  }

  Future<bool> _onWillPop() async {
    // 저장된 이력이 없으면 (즉, 첫 번째 문제이면)
    if (_progressHistory.isEmpty) {
      // 기본 뒤로가기 동작을 허용 (화면 나가기)
      return true;
    }

    // 저장된 이력이 있으면 (즉, 두 번째 문제 이상이면)
    setState(() {
      // 가장 최근에 저장된 문제 정보를 리스트에서 꺼냄
      final previousProgress = _progressHistory.removeLast();

      // 현재 화면의 문제와 선택된 답을 이전 상태로 되돌림
      _currentQuestion = previousProgress.question;
      _selectedAnswer = previousProgress.selectedAnswer;
      _questionNumber--; // 문제 번호도 하나 줄임
      _isLoading = false;
    });

    // 기본 뒤로가기 동작을 막음 (화면이 나가지 않음)
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(title: const Text('레벨 테스트')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 20),
            Text('오류 발생', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ],
        ),
      );
    }
    if (_currentQuestion == null) {
      return const Center(child: Text('문제를 불러오지 못했습니다.'));
    }

    // 옵션 Map의 키('A', 'B', 'C', 'D')를 리스트로 변환하여 사용합니다.
    final optionKeys = _currentQuestion!.options.keys.toList();

    return Column(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: Text('$_questionNumber / $_totalQuestions',
              style: const TextStyle(fontSize: 16, color: Colors.black54)),
        ),
        const SizedBox(height: 20),
        if (_currentQuestion!.passage != null && _currentQuestion!.passage!.isNotEmpty) ...[
          Container(
            height: 150, // 지문 영역의 높이를 고정하거나 조절할 수 있습니다.
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SingleChildScrollView( // 긴 지문일 경우 스크롤 가능하도록
              child: Text(
                _currentQuestion!.passage!,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
        ],
        if (_currentQuestion!.audioScenario != null && _currentQuestion!.audioScenario!.isNotEmpty) ...[
          Card(
            color: Colors.lightBlue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    '아래 버튼을 눌러 듣기 문제를 들어보세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _speak(_currentQuestion!.audioScenario!), // TTS 함수 호출
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('재생하기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
        ],
        Text(
          // 지문이 있을 경우, 안내 문구를 변경합니다.
          _currentQuestion!.passage != null ? '지문을 읽고 알맞은 답을 고르세요' : '다음 질문에 알맞은 답을 고르세요',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Text(_currentQuestion!.text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 30),
        Expanded(
          child: ListView.builder(
            // itemCount는 옵션의 개수와 동일
            itemCount: optionKeys.length,
            itemBuilder: (context, index) {
              // 'A', 'B', 'C', 'D' ...
              final key = optionKeys[index];
              // '답변 내용1', '답변 내용2' ...
              final optionText = _currentQuestion!.options[key]!;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: RadioListTile<String>(
                  // 화면에는 전체 텍스트를 보여줍니다.
                  title: Text(optionText, style: const TextStyle(fontSize: 16)),
                  // Radio의 값으로는 알파벳 키를 사용합니다.
                  value: key,
                  // 현재 선택된 알파벳 키와 비교합니다.
                  groupValue: _selectedAnswer,
                  // 선택 시, _selectedAnswer에 알파벳 키를 저장합니다.
                  onChanged: (value) => setState(() => _selectedAnswer = value),
                  activeColor: Colors.green,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _submitAndNext,
          child: Text(_questionNumber == _totalQuestions ? '결과 보기' : '다음'),
        ),
      ],
    );
  }
}

class LevelTestResultScreen extends StatefulWidget {
  final String sessionId;
  final bool isMiniTest;

  const LevelTestResultScreen({
    Key? key,
    required this.sessionId,
    this.isMiniTest = false,
  }) : super(key: key);

  @override
  _LevelTestResultScreenState createState() => _LevelTestResultScreenState();
}

class _LevelTestResultScreenState extends State<LevelTestResultScreen> {
  // 👈 1. ApiService 인스턴스를 가져옵니다.
  final ApiService _apiService = ApiService();
  final LevelTestApiService _levelTestApiService = LevelTestApiService(); // 기존 서비스도 유지

  bool _isLoading = true;
  Map<String, dynamic>? _resultData;
  String? _errorMessage;

  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _fetchAndSaveResults(); // 👈 2. 결과를 가져오고 저장하는 함수를 호출하도록 변경
  }

  // 👈 3. 결과를 가져온 후, DB에 저장하는 로직을 통합한 새 함수
  Future<void> _fetchAndSaveResults() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. AI 서버에서 레벨 테스트 결과 가져오기 (기존과 동일)
      final response = await _levelTestApiService.completeAssessment(AppState.userId!, widget.sessionId);
      print('### 결과 API 응답: ${response.toString()}');

      if (response['success'] == true && response['data'] != null) {
        final responseData = response['data'];
        final userProfileFromAI = responseData['user_profile'] ?? {};
        final assessedLevel = userProfileFromAI['assessed_level'];

        // 관리자 여부 등 다른 정보 업데이트 (기존과 동일)
        _isAdmin = userProfileFromAI['is_admin'] ?? false;
        if (responseData['recommendations'] != null) {
          AppState.recommendations = List<String>.from(responseData['recommendations']);
        }
        if (responseData['next_steps'] != null) {
          AppState.nextSteps = List<String>.from(responseData['next_steps']);
        }

        // assessedLevel 값이 있을 경우에만 DB 저장 및 프로필 갱신 수행
        if (assessedLevel != null) {
          // 2. 백엔드 DB에 새로운 레벨 저장 (기존과 동일)
          await _apiService.updateUserLevel(
            userId: AppState.userEmail!, // 백엔드에서는 식별자로 이메일을 사용
            assessedLevel: assessedLevel,
          );

          // 3. [핵심 추가] DB 저장 성공 후, 최신 프로필 정보를 다시 불러와 AppState를 업데이트합니다.
          print('✅ 레벨 저장 성공. 최신 프로필 정보를 다시 불러옵니다...');
          final updatedUserProfile = await _apiService.getUserProfile();
          AppState.updateFromProfile(updatedUserProfile);
          print('✅ AppState 업데이트 완료. 새로운 레벨: ${AppState.userLevel}');
        }

        // UI에 결과 데이터를 표시하기 위해 상태 업데이트 (기존과 동일)
        setState(() {
          _resultData = responseData;
        });

      } else {
        _handleError(response['error']?.toString() ?? '결과를 불러오는 데 실패했습니다.');
      }
    } catch (e) {
      _handleError('서버에 연결할 수 없습니다: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 에러 처리 헬퍼 함수
  void _handleError(String message) {
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar에는 뒤로가기 버튼을 자동으로 만들지 않도록 설정
      appBar: AppBar(title: const Text('테스트 결과'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          // _isLoading, _errorMessage, _resultData 상태에 따라 다른 화면을 보여주는
          // _buildContent 헬퍼 함수를 호출합니다.
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }
    if (_resultData == null) {
      return const Center(child: Text('결과 데이터가 없습니다.'));
    }

    final userProfile = _resultData!['user_profile'] ?? {};
    final level = userProfile['assessed_level'] ?? 'N/A';
    final strengths = List<String>.from(userProfile['strengths'] ?? []);
    final weaknesses = List<String>.from(userProfile['areas_to_improve'] ?? []);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        const Icon(Icons.emoji_events_outlined, color: Colors.amber, size: 80),
        const SizedBox(height: 20),
        Text('테스트 완료!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text('당신의 언어 레벨은...',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            level,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800),
          ),
        ),
        const SizedBox(height: 24),
        if (strengths.isNotEmpty) ...[
          Text('👍 강점: ${strengths.join(', ')}'),
          const SizedBox(height: 8),
        ],
        if (weaknesses.isNotEmpty) ...[
          Text('💪 개선점: ${weaknesses.join(', ')}'),
        ],
        const Spacer(flex: 3),
        ElevatedButton(
          onPressed: () {
            // [핵심 로직] isMiniTest 값에 따라 분기 처리
            if (widget.isMiniTest) {
              // 미니 테스트일 경우: HomeScreen으로 이동
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => HomeScreen(isAdmin: ApiService().isAdmin)),
                    (route) => false,
              );
            } else {
              // 일반 레벨 테스트일 경우: GoalSettingScreen으로 이동
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const GoalSettingScreen()),
                    (route) => false,
              );
            }
          },
          // 버튼 텍스트도 상황에 맞게 변경
          child: Text(widget.isMiniTest ? '메인 화면으로' : '다음 단계로 (학습 목표 설정)'),
        ),
        const Spacer(),
      ],
    );
  }
}

// 메인 화면
class HomeScreen extends StatefulWidget {
  // ▼▼▼ 여기에 isAdmin 변수를 추가합니다. ▼▼▼
  final bool isAdmin;
  final bool refresh;

  const HomeScreen({
    super.key,
    required this.isAdmin,
    this.refresh = false, // 👈 기본값은 false로 설정
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late TabController _communityTabController;
  final List<String> _communityTabs = ['자유게시판', '질문게시판', '정보공유', '스터디모집'];
  static const List<String> _titles = ['Learning', '단어장', '학습', '상황별 회화', '커뮤니티'];

  // HomePageContent를 직접 제어하기 위한 GlobalKey
  final GlobalKey<_HomePageContentState> _homePageKey = GlobalKey<_HomePageContentState>();
  final GlobalKey<_StudyScreenState> _studyScreenKey = GlobalKey<_StudyScreenState>();

  @override
  void initState() {
    super.initState();
    _communityTabController = TabController(length: _communityTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _communityTabController.dispose();
    super.dispose();
  }

  // 홈 화면 데이터를 새로고침해야 할 때 호출되는 함수
  void refreshHomeScreen() {
    // GlobalKey를 통해 HomePageContent의 상태 새로고침 함수를 직접 호출
    _homePageKey.currentState?.loadHomeData();
  }

  // AppState를 업데이트하는 함수
  void _updateStateWithProfileData(Map<String, dynamic> profileData) {
    if (mounted) {
      setState(() {
        AppState.updateFromProfile(profileData);
      });
      // 목표 설정 후 홈 화면 데이터 즉시 새로고침
      refreshHomeScreen();
    }
  }

  // ▼▼▼ [핵심 수정] 탭 선택 시 로직 변경 ▼▼▼
  void _onItemTapped(int index) {
    // 만약 사용자가 홈 탭(index 0)을 선택했다면, 데이터를 새로고침합니다.
    if (index == 0) {
      refreshHomeScreen();
    }

    // 선택된 탭의 인덱스를 상태에 반영하여 화면을 전환합니다.
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 페이지 목록을 build 메서드 안으로 이동
    final List<Widget> _pages = <Widget>[
      HomePageContent(
        key: _homePageKey, // GlobalKey 연결
        onNavigate: refreshHomeScreen,
      ),
      VocabularyScreen(),
      StudyScreen(key: _studyScreenKey),
      SituationScreen(),
      CommunityScreen(tabController: _communityTabController),
    ];

    return Scaffold(
      drawer: MyInfoDrawer(onRefresh: refreshHomeScreen),
      appBar: AppBar(
        leading: Builder(
          builder: (innerContext) {
            return IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => Scaffold.of(innerContext).openDrawer(),
            );
          },
        ),
        title: Text(_titles[_selectedIndex]),
        bottom: _selectedIndex == 4
            ? TabBar(
          controller: _communityTabController,
          tabs: _communityTabs.map((String title) => Tab(text: title)).toList(),
        ) : null,
        actions: [
          // 홈 탭(첫 번째 화면)일 때만 아이콘들을 표시합니다.
          if (_selectedIndex == 0) ...[
            // [추가] 즐겨찾기 아이콘 버튼
            IconButton(
              tooltip: '즐겨찾기 보기',
              icon: const Icon(Icons.star_outline),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const FavoritesScreen()));
              },
            ),
            // 기존 알림 아이콘 버튼
            IconButton(
              tooltip: '알림 보기',
              icon: const Icon(Icons.notifications_none),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationPage()));
              },
            ),
            // 기존 설정 아이콘 버튼
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen(
                    userProfile: UserProfile(
                      id: AppState.userId ?? '',
                      email: AppState.userEmail ?? '',
                      isAdmin: widget.isAdmin,
                      userMetadata: { 'name': AppState.userName ?? '', 'level': AppState.userLevel ?? '' },
                    ),
                  )),
                );
              },
            ),
          ],
          if (_selectedIndex == 2)
            IconButton(
              tooltip: '새로고침',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                // GlobalKey를 통해 StudyScreen의 새로고침 함수를 호출합니다.
                _studyScreenKey.currentState?.refreshCurrentTab();
              },
            ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.book_outlined), label: '단어장'),
          BottomNavigationBarItem(icon: Icon(Icons.school_outlined), label: '학습'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: '상황별 회화'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), label: '커뮤니티'),
        ],
      ),
    );
  }
}

class HomePageContent extends StatefulWidget {
  final VoidCallback onNavigate;
  const HomePageContent({super.key, required this.onNavigate});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> with AutomaticKeepAliveClientMixin {
  final ApiService _apiService = ApiService();

  Map<String, int> _todayProgress = { 'conversation': 0, 'grammar': 0, 'pronunciation': 0 };
  Map<String, dynamic>? _vocabAnalysis;
  Set<int> _thisWeekAttendedDays = {};
  Map<String, dynamic>? _feedbackData;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    loadHomeData();
  }

  // 외부(HomeScreen)에서도 호출할 수 있도록 함수 이름을 변경
  Future<void> loadHomeData() async {
    try {
      final results = await Future.wait([
        _apiService.getTodayProgress(),
        _apiService.getVocabularyAnalysis(),
        _apiService.getAttendanceHistory(),
        _apiService.getDailyFeedback(),
        _apiService.getUserProfile(),
      ]);

      if (mounted) {
        final userProfile = results[4] as Map<String, dynamic>;

        // ▼▼▼ [핵심 디버깅 코드] ▼▼▼
        // API로부터 받은 프로필 데이터 전체를 콘솔에 출력합니다.
        // learning_goals가 제대로 오는지 여기서 확인할 수 있습니다.
        print("--- [홈 화면 프로필 데이터] API 응답 ---");
        print(userProfile);
        print("------------------------------------");

        // 만약 learning_goals 필드가 null이라면 경고 메시지를 출력합니다.
        if (userProfile['learning_goals'] == null) {
          print("⚠️ 경고: API 응답에 'learning_goals' 필드가 없습니다. 목표 설정 UI가 표시됩니다.");
        }
        // ▲▲▲ [디버깅 코드 끝] ▲▲▲

        AppState.updateFromProfile(userProfile);

        final attendanceHistory = (results[2] as List).map((item) => AttendanceRecord.fromJson(item)).toList();
        final now = DateTime.now();
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final Set<int> attendedDays = {};
        for (var record in attendanceHistory) {
          final recordDate = record.date;
          if (recordDate.isAfter(startOfWeek.subtract(const Duration(days: 1))) && recordDate.isBefore(now.add(const Duration(days: 1)))) {
            attendedDays.add(recordDate.weekday);
          }
        }

        setState(() {
          _todayProgress = results[0] as Map<String, int>;
          _vocabAnalysis = results[1] as Map<String, dynamic>;
          _thisWeekAttendedDays = attendedDays;
          _feedbackData = results[3] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      print('홈 데이터 조회 오류: $e');
      if (mounted) setState(() {
        _vocabAnalysis = null;
        _thisWeekAttendedDays = {};
        _feedbackData = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // [수정] ListView를 사용하여 오버플로우 에러를 방지하고, RefreshIndicator를 다시 활성화합니다.
    return RefreshIndicator(
      onRefresh: loadHomeData, // 화면을 당겨서 새로고침하는 기능
      child: ListView( // Column 대신 ListView 사용
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildProfileSection(),
          const SizedBox(height: 12), // 간격을 20 -> 12로 줄여서 최대한 한 화면에 보이도록 함
          _buildProgressFeedbackCard(),
          const SizedBox(height: 12),
          _buildVocabularyTestSection(),
          const SizedBox(height: 12),
          _buildVocabularyAnalysisSection(),
          const SizedBox(height: 12),
          _buildAttendanceCheckSection(context),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    final userName = AppState.userName;
    final userLevel = AppState.userLevel;
    final learningLanguage = AppState.targetLanguage;
    // AppState에서 learning_goals를 직접 가져옵니다.
    final Map<String, dynamic>? goalsMap = AppState.learningGoals;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(userName ?? AppState.selectedCharacterName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Image.asset(AppState.selectedCharacterImage, width: 100, height: 100, errorBuilder: (c, e, s) => const Icon(Icons.image_not_supported, size: 100)),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (learningLanguage != null)
                        RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontFamily: 'Pretendard'),
                            children: <TextSpan>[
                              const TextSpan(text: '회화 학습 언어: '),
                              TextSpan(text: learningLanguage, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      if (userLevel != null)
                        RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontFamily: 'Pretendard'),
                            children: <TextSpan>[
                              const TextSpan(text: '레벨: '),
                              TextSpan(text: userLevel, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 6,
              // ▼▼▼ [핵심 수정] goalsMap이 null이 아닌지 확인하여 분기 처리 ▼▼▼
              child: goalsMap != null && goalsMap.isNotEmpty
                  ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text("오늘의 목표", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // ▼▼▼ [핵심 수정] 키 이름을 API 응답에 맞게 변경 ▼▼▼
                  if ((goalsMap['conversation_goal'] ?? 0) > 0)
                    _buildGoalIndicator(icon: Icons.chat_bubble_outline, color: Colors.orange, title: '회화', progress: _todayProgress['conversation'] ?? 0, goal: (goalsMap['conversation_goal'] ?? 0) as int, unit: '분'),

                  if ((goalsMap['grammar_goal'] ?? 0) > 0) const SizedBox(height: 12),

                  if ((goalsMap['grammar_goal'] ?? 0) > 0)
                    _buildGoalIndicator(icon: Icons.menu_book_outlined, color: Colors.blue, title: '문법', progress: _todayProgress['grammar'] ?? 0, goal: (goalsMap['grammar_goal'] ?? 0) as int, unit: '회'),

                  if ((goalsMap['pronunciation_goal'] ?? 0) > 0) const SizedBox(height: 12),

                  if ((goalsMap['pronunciation_goal'] ?? 0) > 0)
                    _buildGoalIndicator(icon: Icons.mic_none, color: Colors.green, title: '발음', progress: _todayProgress['pronunciation'] ?? 0, goal: (goalsMap['pronunciation_goal'] ?? 0) as int, unit: '회'),
                ],
              )
                  : Center(
                child: GestureDetector(
                  onTap: () {
                    final homeScreenState = context.findAncestorStateOfType<_HomeScreenState>();
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const GoalSettingScreen())).then((result) {
                      if (result == true) {
                        homeScreenState?.refreshHomeScreen();
                      }
                    });
                  },
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag_outlined, color: Colors.grey, size: 40),
                      SizedBox(height: 8),
                      Text('학습 목표를 설정하고\n계획을 시작해보세요!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.5)),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildProgressFeedbackCard() {
    // AppState를 직접 참조하는 대신, loadHomeData를 통해 받은 _feedbackData를 사용합니다.
    if (_feedbackData == null) {
      return const SizedBox.shrink(); // 데이터가 없으면 표시하지 않음
    }

    // 백엔드에서 받은 데이터를 사용합니다.
    final String feedbackMessage = _feedbackData!['message'] ?? '학습을 시작해보세요!';
    final IconData feedbackIcon = _getIconFromString(_feedbackData!['icon']);
    final Color feedbackColor = _getColorFromString(_feedbackData!['color']);

    return Card(
      color: feedbackColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(feedbackIcon, color: feedbackColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                feedbackMessage,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconFromString(String? iconName) {
    switch (iconName) {
      case 'emoji_events':
        return Icons.emoji_events;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'directions_run':
        return Icons.directions_run;
      case 'rocket_launch':
        return Icons.rocket_launch;
      default:
        return Icons.task_alt;
    }
  }

  Color _getColorFromString(String? colorName) {
    switch (colorName) {
      case 'amber':
        return Colors.amber;
      case 'deepOrange':
        return Colors.deepOrange;
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildVocabularyTestSection() {
    return GestureDetector( // Card를 GestureDetector로 감싸서 탭 이벤트를 받도록 함
      onTap: () {
        // 탭했을 때 isMiniTest 플래그를 true로 설정하여 LevelTestScreen으로 이동
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const LevelTestScreen(isMiniTest: true),
          ),
        );
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(Icons.bar_chart, color: Colors.green, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('나의 레벨은 어느 정도일까?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('새로운 문제 4문제 더 풀고 알아보러 가기', style: TextStyle(color: Colors.grey))
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16)
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVocabularyAnalysisSection() {
    if (_vocabAnalysis == null) {
      return const Card(child: Padding(padding: EdgeInsets.all(16.0), child: Center(child: Text('어휘 분석 데이터를 불러오는 중...'))));
    }

    final totalCount = _vocabAnalysis!['total_count'] ?? 0;
    final memorizedCount = _vocabAnalysis!['memorized_count'] ?? 0;
    final notMemorizedCount = _vocabAnalysis!['not_memorized_count'] ?? 0;
    // 'review_accuracy' 대신 'memorization_rate' 키를 사용합니다.
    final memorizationRate = (_vocabAnalysis!['memorization_rate'] ?? 0.0).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('어휘 분석', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: const [
                    CircleAvatar(radius: 5, backgroundColor: Colors.green),
                    SizedBox(width: 4),
                    Text('암기율', style: TextStyle(color: Colors.grey)),
                  ],
                )
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('전체 단어: $totalCount', style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Text('암기한 단어: $memorizedCount', style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Text('복습할 단어: $notMemorizedCount', style: TextStyle(color: Colors.grey.shade600))
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 60,
                  width: 20,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(color: Colors.grey.shade300),
                      Container(
                        height: 60.0 * (memorizationRate / 100.0), // 암기율에 따라 높이 조절
                        color: Colors.green, // 색상 변경
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  children: [
                    Text(memorizationRate.toStringAsFixed(0), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Text('%', style: TextStyle(color: Colors.grey))
                  ],
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCheckSection(BuildContext context) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];

    return GestureDetector(
      onTap: () async { // 1. onTap 콜백을 async 함수로 변경
        // 2. AttendancePage로 이동하고, 해당 화면이 닫힐 때까지 기다립니다.
        await Navigator.of(context).push(_createSlideRoute(const AttendancePage()));

        // 3. 사용자가 뒤로가기로 돌아오면, 홈 화면 데이터를 새로고침합니다.
        print("✅ 출석 체크 화면에서 복귀. 홈 화면 데이터를 새로고침합니다.");
        loadHomeData();
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Text('출석 체크', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              // 월요일부터 일요일까지 7개의 요일 서클을 동적으로 생성
              ...List.generate(7, (index) {
                final dayOfWeek = index + 1; // 월요일=1, ... 일요일=7
                final isChecked = _thisWeekAttendedDays.contains(dayOfWeek);
                return _buildDayCircle(days[index], isChecked: isChecked);
              }),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayCircle(String day, {bool isChecked = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isChecked ? Colors.lightBlueAccent : Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: isChecked
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : Text(day, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ),
    );
  }

  Widget _buildGoalIndicator({
    required IconData icon,
    required Color color,
    required String title,
    required int progress,
    required int goal,
    required String unit,
  }) {
    final double progressPercent = goal > 0 ? progress / goal : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(
              '$progress / $goal $unit',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progressPercent,
          backgroundColor: color.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          borderRadius: BorderRadius.circular(10),
          minHeight: 8,
        ),
      ],
    );
  }
}

class MyInfoDrawer extends StatelessWidget {
  final VoidCallback onRefresh;

  const MyInfoDrawer({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final String characterImage = AppState.selectedCharacterImage;
    final String? displayName = AppState.userName;
    final String? displayEmail = AppState.userEmail;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(displayName ?? AppState.selectedCharacterName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            accountEmail: Text(displayEmail ?? '이메일 정보 없음'),
            currentAccountPicture: CircleAvatar(
              backgroundImage: AssetImage(characterImage),
              backgroundColor: Colors.white,
            ),
            decoration: BoxDecoration(color: Colors.green.shade700),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('프로필 관리'),
            onTap: () async { // 1. onTap을 async 함수로 변경
              Navigator.pop(context); // 먼저 Drawer를 닫습니다.
              // 2. ProfileScreen으로 이동하고, 해당 화면이 닫힐 때까지 기다립니다.
              await Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen()));
              onRefresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('나의 학습 통계'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const StatisticsScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.show_chart_outlined),
            title: const Text('나의 학습 진척도'),
            onTap: () {
              Navigator.pop(context);
              // 새로 만든 ProgressScreen으로 이동하도록 설정
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ProgressScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('학습 목표 설정'),
            onTap: () async {
              Navigator.pop(context); // Drawer를 먼저 닫습니다.

              // ▼▼▼ [핵심 수정] ▼▼▼
              // GoalSettingScreen으로 이동하고, 결과가 돌아올 때까지 기다립니다.
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GoalSettingScreen()),
              );

              // 만약 GoalSettingScreen에서 'true' 값을 돌려받았다면, 홈 화면을 새로고침합니다.
              if (result == true) {
                print("✅ 학습 목표 변경 감지. 홈 화면을 새로고침합니다.");
                onRefresh();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('포인트 교환소'),
            onTap: () {
              Navigator.pop(context); // Drawer를 닫습니다.
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PointExchangeScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
            onTap: () async {
              await ApiService().logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => InitialScreen()),
                      (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final ApiService _apiService = ApiService();
  late Future<StatisticsResponse> _statisticsFuture;

  @override
  void initState() {
    super.initState();
    _statisticsFuture = _apiService.getStatistics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('나의 학습 통계'),
      ),
      body: FutureBuilder<StatisticsResponse>(
        future: _statisticsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('데이터가 없습니다.'));
          }

          final stats = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildOverallStatsCard(stats.overallStats),
              const SizedBox(height: 20),
              _buildFeedbackCard(stats.feedback),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverallStatsCard(OverallStats overall) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📊 누적 학습량', style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: Colors.orange),
              title: const Text('총 회화 학습'),
              trailing: Text('${overall.totalConversationDuration} 분', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined, color: Colors.blue),
              title: const Text('총 문법 학습'),
              trailing: Text('${overall.totalGrammarCount} 회', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.mic_none, color: Colors.green),
              title: const Text('총 발음 학습'),
              trailing: Text('${overall.totalPronunciationCount} 회', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackCard(String? feedback) {
    // 피드백 데이터가 없거나 비어있으면 아무것도 표시하지 않음
    if (feedback == null || feedback.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '학습 방향 개선안',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(feedback, style: const TextStyle(height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(String title, double value, Color color) {
    final percentage = value.clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            Text('${percentage.toStringAsFixed(1)} %', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: percentage / 100,
          minHeight: 10,
          backgroundColor: color.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          borderRadius: BorderRadius.circular(5),
        ),
      ],
    );
  }
}

class ProfileScreen extends StatefulWidget {
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  @override
  Widget build(BuildContext context) {
    final String? userName = AppState.userName;
    final String? userEmail = AppState.userEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('프로필 관리')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildProfileHeader(context, name: userName, email: userEmail),
          const SizedBox(height: 24),
          _buildInfoCard(),
          const SizedBox(height: 24),
          _buildDangerZone(),
        ],
      ),
    );
  }

  // 👈 3. _buildProfileHeader 위젯이 이름과 이메일을 파라미터로 받도록 수정합니다.
  Widget _buildProfileHeader(BuildContext context, {String? name, String? email}) {
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundImage: AssetImage(AppState.selectedCharacterImage),
          backgroundColor: Colors.grey.shade200,
        ),
        const SizedBox(height: 16),
        Text(
          name ?? '사용자',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          email ?? '이메일 정보 없음',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfileEditScreen()),
            ).then((value) {
              if (value == true) {
                setState(() {});
              }
            });
          },
          icon: const Icon(Icons.edit),
          label: const Text('이름 수정'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  // _buildInfoCard 위젯은 이미 AppState를 사용하고 있으므로 수정할 필요가 없습니다.
  Widget _buildInfoCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('나의 레벨'),
            trailing: Text(AppState.userLevel ?? '테스트 미완료', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('학습 언어'),
            trailing: Text(AppState.targetLanguage ?? '미설정', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // _buildDangerZone 위젯은 수정할 필요가 없습니다.
  Widget _buildDangerZone() {
    return Card(
      color: Colors.red.shade50,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.password, color: Colors.red.shade700),
            title: Text('비밀번호 변경', style: TextStyle(color: Colors.red.shade700)),
            onTap: () {
              // ✅ 비밀번호 변경 화면으로 이동
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PasswordChangeScreen()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Colors.red.shade700),
            title: Text('회원 탈퇴', style: TextStyle(color: Colors.red.shade700)),
            onTap: () {
              // ✅ 회원 탈퇴 화면으로 이동
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AccountDeleteScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final ApiService _apiService = ApiService();
  late Future<Map<String, dynamic>> _attendanceDataFuture;
  Set<DateTime> _attendedDays = {};

  @override
  void initState() {
    super.initState();
    _attendanceDataFuture = _loadAttendanceData();
  }

  Future<Map<String, dynamic>> _loadAttendanceData() async {
    try {
      // 통계와 기록을 동시에 병렬로 불러옵니다.
      final results = await Future.wait([
        _apiService.getAttendanceStats(),
        _apiService.getAttendanceHistory(),
      ]);

      final stats = AttendanceStats.fromJson(results[0] as Map<String, dynamic>);
      final history = (results[1] as List).map((item) => AttendanceRecord.fromJson(item)).toList();

      // 달력에 표시할 출석 날짜 Set을 업데이트합니다.
      _attendedDays = history.map((rec) => DateTime.utc(rec.date.year, rec.date.month, rec.date.day)).toSet();

      return {'stats': stats, 'history': history};
    } catch (e) {
      // 오류가 발생하면 재시도할 수 있도록 오류를 다시 던집니다.
      rethrow;
    }
  }

  Future<void> _handleCheckIn() async {
    try {
      await _apiService.checkIn();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 오늘 출석이 완료되었습니다!')),
      );
      // 성공 시 데이터 새로고침
      setState(() {
        _attendanceDataFuture = _loadAttendanceData();
      });
    } on ApiException catch (e) {
      // [수정] "Already checked in" 메시지를 포함하는지 확인하는 대신,
      // 백엔드에서 보낸 메시지를 그대로 사용합니다.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // "🙂 오늘은 이미 출석했습니다." 와 같은 구체적인 메시지가 표시됩니다.
          content: Text('🙂 ${e.message}'),
          backgroundColor: Colors.orange, // 경고의 의미로 주황색 사용
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('출석 체크')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _attendanceDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('데이터를 불러오는 데 실패했습니다: ${snapshot.error}'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => setState(() {
                      _attendanceDataFuture = _loadAttendanceData();
                    }),
                    child: const Text('재시도'),
                  )
                ],
              ),
            );
          }

          final stats = snapshot.data!['stats'] as AttendanceStats;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildStatsCard(stats),
              const SizedBox(height: 20),
              _buildCalendarCard(),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _handleCheckIn,
                child: const Text('오늘 날짜 출석하기'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatsCard(AttendanceStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('총 출석일', stats.totalDays.toString(), '일'),
            _buildStatItem('최대 연속 출석', stats.longestStreak.toString(), '일'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String title, String value, String unit) {
    return Column(
      children: [
        Text(title, style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            children: [
              TextSpan(text: value),
              TextSpan(text: ' $unit', style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: DateTime.now(),
          headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (_attendedDays.contains(day)) {
                return Positioned(
                  bottom: 1,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }
              return null;
            },
          ),
        ),
      ),
    );
  }
}

// ▼▼▼ [추가] 오늘의 학습 추천 화면 ▼▼▼
class RecommendedStudyScreen extends StatelessWidget {
  const RecommendedStudyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    print("\n--- [추천 학습 화면 디버그] ---");
    print("  - [디버그 3] AppState.recommendations: ${AppState.recommendations}");
    print("  - [디버그 3] AppState.nextSteps: ${AppState.nextSteps}");
    print("----------------------------\n");
    // AppState에서 추천 학습 데이터 가져오기
    final recommendations = AppState.recommendations;
    final nextSteps = AppState.nextSteps;

    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘의 추천 학습'),
      ),
      body: recommendations.isNotEmpty || nextSteps.isNotEmpty
          ? ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (recommendations.isNotEmpty) ...[
            Text('🎯 추천 학습 목표', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (var goal in recommendations)
              Card(
                margin: const EdgeInsets.only(bottom: 8.0),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text("✔️  $goal", style: const TextStyle(fontSize: 16)),
                ),
              ),
            const SizedBox(height: 24),
          ],
          if (nextSteps.isNotEmpty) ...[
            Text('🚀 다음 학습 단계', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (var step in nextSteps)
              Card(
                margin: const EdgeInsets.only(bottom: 8.0),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text("👉  $step", style: const TextStyle(fontSize: 16)),
                ),
              ),
          ]
        ],
      )
          : const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('추천 학습을 보려면\n먼저 레벨 테스트를 완료해주세요!', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

// 단어장 메인 화면
class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  _VocabularyScreenState createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ApiService _apiService = ApiService();
  late Future<List<Wordbook>> _wordbooksFuture;

  // 로딩 오버레이를 위한 상태 변수
  bool _isLoadingOverlay = false;
  String _loadingMessage = '';

  // 기존 UI 유지를 위한 변수들
  final _searchController = TextEditingController();
  final Map<String, String> _pickWordbooks = {'#토익/토플': 'assets/TOEIC:TOEFL.txt'};

  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _loadData(); // _loadWordbooks 대신 _loadData 호출
  }

  // 단어장 목록과 통계를 한 번에 불러오는 함수
  Future<void> _loadData() async {
    setState(() {
      _dataFuture = _fetchData();
    });
  }

  Future<Map<String, dynamic>> _fetchData() async {
    final wordbooks = await _apiService.getWordbooks().then(
            (data) => data.map((item) => Wordbook.fromJson(item)).toList()
    );
    final stats = await _apiService.getVocabularyStats();
    return {'wordbooks': wordbooks, 'stats': stats};
  }

  Future<void> _loadWordbooks() async {
    setState(() {
      _wordbooksFuture = _apiService.getWordbooks().then(
              (data) => data.map((item) => Wordbook.fromJson(item)).toList()
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 백엔드 연동 방식으로 수정된 새 단어장 생성 함수
  Future<void> _showCreateWordbookDialog() async {
    final TextEditingController nameController = TextEditingController();
    final formKey = GlobalKey<FormState>(); // 1. Form 키 추가

    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 단어장 생성'),
        content: Form( // 2. Form 위젯으로 감싸기
          key: formKey,
          child: TextFormField( // 3. TextField를 TextFormField로 변경
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: '단어장 이름을 입력하세요'),
            validator: (value) { // 4. validator 추가
              if (value == null || value.trim().isEmpty) {
                return '이름을 입력해야 합니다.';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
          TextButton(
            child: const Text('생성'),
            onPressed: () {
              // 5. Form의 유효성 검사 후 pop
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(nameController.text.trim());
              }
            },
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      try {
        await _apiService.createWordbook(newName);
        _loadData(); // 생성 성공 후 목록 새로고침
      } on ApiException catch(e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      }
    }
  }

  // 백엔드 연동 방식으로 수정된 Pick 단어장 생성 함수
  Future<void> _createWordbookFromFile(String wordbookName, String assetPath) async {
    setState(() {
      _isLoadingOverlay = true;
      _loadingMessage = '단어장을 생성하고 단어를 추가하는 중...';
    });

    try {
      // 1. 단어장 생성
      final newWordbookData = await _apiService.createWordbook(wordbookName);
      final newWordbookId = newWordbookData['id'];

      // 2. 로컬 파일에서 단어와 뜻만 빠르게 읽기 (인터넷 조회 X)
      final String fileContents = await rootBundle.loadString(assetPath);
      final List<String> lines = fileContents.split('\n').where((line) => line.trim().isNotEmpty).toList();

      final List<Map<String, dynamic>> wordsToBatch = [];
      final regex = RegExp(r'^(.+?)\s+\((.+?)\)\s+\/(.*?)\/\s+\((.+?)\)\s+\((.+)\)$');

      for (final line in lines) {
        final match = regex.firstMatch(line.trim());

        // 정규식에 매칭되는 경우, 모든 정보를 추출하여 배치 목록에 추가합니다.
        if (match != null && match.groupCount == 5) {
          final word = match.group(1)!.trim();
          final definition = match.group(2)!.trim();
          // 슬래시(/)를 다시 붙여서 발음기호 형식을 유지합니다.
          final pronunciation = '/${match.group(3)!.trim()}/';
          final partOfSpeech = match.group(4)!.trim();
          final example = match.group(5)!.trim();

          wordsToBatch.add({
            'word': word,
            // 품사를 뜻 앞에 추가하여 "(품사) 뜻" 형태로 저장합니다.
            'definition': '($partOfSpeech) $definition',
            'pronunciation': pronunciation,
            'english_example': example,
          });
        } else {
          // [기존 로직 유지] 만약 새로운 형식에 맞지 않는 줄이 있다면,
          // 기존 방식(단어와 뜻만 추출)으로 파싱을 시도합니다.
          final oldRegex = RegExp(r'(.+?)\s*\((.+)\)');
          final oldMatch = oldRegex.firstMatch(line);
          if (oldMatch != null && oldMatch.groupCount == 2) {
            wordsToBatch.add({
              'word': oldMatch.group(1)!.trim(),
              'definition': oldMatch.group(2)!.trim(),
            });
          }
        }
      }

      // 3. 준비된 단어/뜻 목록을 서버로 한 번에 전송
      if (wordsToBatch.isNotEmpty) {
        await _apiService.addWordsToWordbookBatch(
          wordbookId: newWordbookId,
          words: wordsToBatch,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'$wordbookName' 단어장이 생성되었습니다!")));
        _loadData();
      }

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("단어장 생성 중 오류가 발생했습니다: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOverlay = false;
          _loadingMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // ▼▼▼ [1-3. 검색창 TextField 수정] ▼▼▼
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '모든 단어장에서 검색...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear())
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                // enabled: false, // 👈 이 줄을 삭제하거나 주석 처리
                textInputAction: TextInputAction.search,
                onSubmitted: (query) {
                  if (query.trim().isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => WordSearchResultsScreen(searchQuery: query.trim()),
                      ),
                    );
                  }
                },
              ),
              // ▲▲▲ [1-3. 완료] ▲▲▲
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _dataFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('오류: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: Text('데이터 없음'));
                    }

                    final wordbooks = snapshot.data!['wordbooks'] as List<Wordbook>;
                    final stats = snapshot.data!['stats'] as Map<String, dynamic>;
                    final totalCount = stats['total_count'] ?? 0;
                    final memorizedCount = stats['memorized_count'] ?? 0;
                    final notMemorizedCount = stats['not_memorized_count'] ?? 0;

                    return RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildClickableStatusCard(
                                title: '전체',
                                count: totalCount,
                                color: Colors.blue.shade700,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) =>
                                    FilteredWordsScreen(title: '전체 단어', filterStatus: 'all'))),
                              ),
                              _buildClickableStatusCard(
                                title: '미암기',
                                count: notMemorizedCount,
                                color: Colors.red.shade700,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) =>
                                    FilteredWordsScreen(title: '미암기 단어', filterStatus: 'not_memorized'))),
                              ),
                              _buildClickableStatusCard(
                                title: '암기',
                                count: memorizedCount,
                                color: Colors.green.shade700,
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) =>
                                    FilteredWordsScreen(title: '암기 단어', filterStatus: 'memorized'))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildSectionHeader('단어장 목록'),
                          const SizedBox(height: 10),
                          if (wordbooks.isEmpty)
                            Center(child: Text('생성된 단어장이 없습니다.', style: TextStyle(color: Colors.grey.shade600)))
                          else
                            ...wordbooks.map((wb) {
                              return _buildWordbookItem(wb);
                            }).toList(),
                          const SizedBox(height: 30),
                          _buildSectionHeader('Pick 단어장', showAddButton: false), // 'Pick 단어장' UI 복원
                          Text('버튼을 눌러 추천 단어장을 자동으로 생성하세요', style: TextStyle(color: Colors.grey.shade700)),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _pickWordbooks.entries.map((entry) {
                              return ElevatedButton(
                                child: Text(entry.key),
                                onPressed: _isLoadingOverlay ? null : () {
                                  _createWordbookFromFile(entry.key, entry.value);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // 로딩 오버레이 UI 복원
        if (_isLoadingOverlay)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(_loadingMessage, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // 기존 UI 유지를 위한 헬퍼 위젯들 (수정 없음)
  Widget _buildClickableStatusCard({required String title, required int count, required Color color, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Column(
              children: [
                Text(title, style: TextStyle(fontSize: 16, color: Colors.grey.shade800)),
                const SizedBox(height: 8),
                Text(count.toString(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool showAddButton = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (showAddButton)
          IconButton(icon: const Icon(Icons.add, color: Colors.green), onPressed: _showCreateWordbookDialog),
      ],
    );
  }

  Future<void> _showDeleteWordbookConfirmDialog(Wordbook wordbook) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('단어장 삭제'),
        content: Text("'${wordbook.name}' 단어장을 삭제하시겠습니까?\n단어장 안의 모든 단어가 함께 삭제됩니다."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiService.deleteWordbook(wordbook.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('단어장이 삭제되었습니다.')));
        }
        _loadData(); // 삭제 성공 후 목록 새로고침
      } on ApiException catch(e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: ${e.message}'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildWordbookItem(Wordbook wordbook) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(wordbook.name),
        subtitle: Text('단어 ${wordbook.wordCount}개'),
        leading: const Icon(Icons.book, color: Colors.green),
        onTap: () async {
          // 상세 화면으로 이동 후, 'true' 값을 돌려받으면 목록을 새로고침합니다.
          final shouldRefresh = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (context) => WordbookDetailScreen(wordbook: wordbook)),
          );
          if (shouldRefresh == true) {
            _loadData();
          }
        },
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: Colors.grey.shade600),
          tooltip: '단어장 삭제',
          onPressed: () => _showDeleteWordbookConfirmDialog(wordbook),
        ),
      ),
    );
  }
}

// --- 새로 추가된 부분: 단어 검색 및 추가 화면 ---
class WordSearchScreen extends StatefulWidget {
  @override
  _WordSearchScreenState createState() => _WordSearchScreenState();
}

class _WordSearchScreenState extends State<WordSearchScreen> {
  final _searchController = TextEditingController();
  WordData? _foundWord;
  bool _isLoading = false;
  List<String> _suggestions = [];
  Timer? _debounce;

  // ApiService 인스턴스를 클래스 멤버로 추가합니다.
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    // 사용자가 텍스트 필드에 입력할 때마다 _onSearchChanged 함수가 호출되도록 리스너를 추가합니다.
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ▲▲▲ 수정 완료 ▲▲▲


  // ▼▼▼ [3/3. 검색 및 추천 로직 함수 추가/수정] ▼▼▼

  // 사용자가 입력을 멈췄을 때만 단어 추천을 실행하는 함수 (디바운싱)
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _updateSuggestions();
    });
  }

  // 입력된 텍스트로 시작하는 단어를 로컬 사전(Dictionary)에서 찾아 추천 목록을 업데이트하는 함수
  void _updateSuggestions() {
    final query = _searchController.text.trim().toLowerCase();

    // 한글 입력 시에는 자동완성 비활성화
    final isKorean = RegExp(r'[\u3131-\u318E\uAC00-\uD7A3]').hasMatch(query);

    if (query.isEmpty || isKorean) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }

    // 로컬 사전을 필터링하여 상위 7개의 추천 단어를 찾습니다.
    final matchingWords = Dictionary.contains(query)
        ? [query] // 정확히 일치하는 단어가 있으면 그것만 보여줌
        : Dictionary.words
        .where((word) => word.startsWith(query))
        .take(7)
        .toList();

    setState(() {
      _suggestions = matchingWords;
      _foundWord = null; // 추천 목록이 뜨면 이전에 찾은 단어 정보는 숨김
    });
  }

  // 최종 단어 검색을 실행하는 함수 (기존 로직과 거의 동일)
  void _searchWord([String? wordToSearch]) async {
    final query = wordToSearch ?? _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _foundWord = null;
      _suggestions = [];
      if (wordToSearch != null) {
        _searchController.text = wordToSearch;
      }
    });

    try {
      // 1. ApiService의 새로운 함수를 호출합니다.
      final apiResult = await _apiService.searchWordOnline(query);

      if (mounted) {
        // 2. 백엔드에서 보내준 깔끔한 데이터를 사용하여 WordData 객체를 만듭니다.
        _foundWord = WordData(
          word: apiResult['word'] ?? query,
          pronunciation: apiResult['pronunciation'] ?? '',
          definition: apiResult['definition'] ?? '뜻을 찾을 수 없습니다.',
          englishExample: apiResult['english_example'] ?? '예문을 찾을 수 없습니다.',
        );
      }
    } catch (e) {
      if (mounted) {
        // ApiException의 메시지를 바로 사용
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("검색 실패: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 추천 단어 목록 UI를 만드는 헬퍼 위젯
  Widget _buildSuggestions() {
    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          return ListTile(
            leading: const Icon(Icons.search, color: Colors.grey),
            title: Text(suggestion),
            onTap: () {
              // 추천 단어를 탭하면 해당 단어로 바로 검색 실행
              _searchWord(suggestion);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 단어 추가')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        // Column을 ListView로 변경하여 화면이 스크롤되도록 합니다.
        child: ListView(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '영단어 또는 한글 뜻을 입력하세요',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchWord(),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onSubmitted: (_) => _searchWord(),
              autofocus: true,
            ),

            // 추천 단어 목록을 보여주는 위젯 (수정 없음)
            _buildSuggestions(),

            const SizedBox(height: 20),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              if (_foundWord != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_foundWord!.word, style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(_foundWord!.pronunciation, style: TextStyle(
                            fontSize: 16, color: Colors.grey.shade700)),
                        const Divider(height: 24),
                        const Text('뜻:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(_foundWord!.definition,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 16),
                        const Text('예문:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          _foundWord!.englishExample,
                          style: TextStyle(fontSize: 16,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, _foundWord),
                          child: const Text('이 단어 추가하기'),
                        )
                      ],
                    ),
                  ),
                )
              else
                if (_suggestions.isEmpty)
                // Expanded를 제거하고, 화면 중앙에 안내 문구를 표시하기 위해 Padding을 추가합니다.
                  const Padding(
                    padding: EdgeInsets.only(top: 60), // 검색창과의 간격
                    child: Center(child: Text('단어를 검색해 주세요.')),
                  ),
          ],
        ),
      ),
    );
  }
}

// --- 새로 추가된 부분: 단어장 생성 화면 ---
class WordbookCreateScreen extends StatefulWidget {
  @override
  _WordbookCreateScreenState createState() => _WordbookCreateScreenState();
}

class _WordbookCreateScreenState extends State<WordbookCreateScreen> {
  final TextEditingController _nameController = TextEditingController();

  void _createWordbook() {
    if (_nameController.text.trim().isNotEmpty) {
      Navigator.pop(context, _nameController.text.trim());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('단어장 이름을 입력해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F1E8),
      appBar: AppBar(
        title: Text(
          '새 단어장 만들기',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.brown.shade700),
        ),
        backgroundColor: Color(0xFFF5F1E8),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.brown.shade700),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '단어장 이름',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              autofocus: true,
            ),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _createWordbook,
                child: Text('완료'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WordbookDetailScreen extends StatefulWidget {
  final Wordbook wordbook;
  const WordbookDetailScreen({Key? key, required this.wordbook}) : super(key: key);

  @override
  _WordbookDetailScreenState createState() => _WordbookDetailScreenState();
}

class _WordbookDetailScreenState extends State<WordbookDetailScreen> {
  final ApiService _apiService = ApiService();

  // late Future<List<UserWord>> _wordsFuture; // FutureBuilder를 직접 사용하지 않으므로 변경
  bool _hasChanges = false;

  // ---  검색 기능을 위한 상태 변수 추가 ---
  final _searchController = TextEditingController();
  List<UserWord> _allWords = []; // API로부터 받은 모든 단어를 저장
  List<UserWord> _filteredWords = []; // 검색 결과로 필터링된 단어를 저장
  bool _isLoading = true; // 로딩 상태 관리

  @override
  void initState() {
    super.initState();
    _loadWords();
    // 검색창에 텍스트가 입력될 때마다 _filterWords 함수 호출
    _searchController.addListener(_filterWords);
  }

  @override
  void dispose() {
    _searchController.dispose(); // 컨트롤러 리소스 해제
    super.dispose();
  }

  // API로부터 단어를 불러와 상태에 저장하는 함수
  Future<void> _loadWords() async {
    setState(() => _isLoading = true);
    try {
      final details = await _apiService.getWordbookDetails(widget.wordbook.id);
      final words = (details['words'] as List).map((item) =>
          UserWord.fromJson(item)).toList();
      if (mounted) {
        setState(() {
          _allWords = words;
          _filteredWords = words; // 처음에는 모든 단어를 보여줌
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('단어를 불러오지 못했습니다: $e')),
        );
      }
    }
  }

  // 검색 쿼리에 따라 단어 목록을 필터링하는 함수
  void _filterWords() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredWords = _allWords.where((word) {
        final wordLower = word.word.toLowerCase();
        final definitionLower = word.definition.toLowerCase();
        return wordLower.contains(query) || definitionLower.contains(query);
      }).toList();
    });
  }

  // 단어 추가 화면으로 이동하는 함수
  void _navigateAndAddWord() async {
    final newWordRaw = await Navigator.push<WordData>(
      context,
      MaterialPageRoute(builder: (context) => WordSearchScreen()),
    );

    if (newWordRaw != null) {
      try {
        await _apiService.addWordToWordbook(
          wordbookId: widget.wordbook.id,
          word: newWordRaw.word,
          definition: newWordRaw.definition, // ◀◀ 품사 결합 로직 제거
          pronunciation: newWordRaw.pronunciation,
          englishExample: newWordRaw.englishExample,
        );

        _loadWords(); // 추가 성공 후 목록 새로고침
        setState(() => _hasChanges = true);
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      }
    }
  }

  // [수정된 함수] 단어 삭제 확인 및 API 호출 함수
  Future<void> _showDeleteConfirmDialog(UserWord wordToDelete) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('단어 삭제'),
            content: Text("'${wordToDelete.word}' 단어를 삭제하시겠습니까?"),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('취소')),
              TextButton(
                child: const Text('삭제', style: TextStyle(color: Colors.red)),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        await _apiService.deleteWord(wordToDelete.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('단어가 삭제되었습니다.')));
        }
        _loadWords();
        setState(() => _hasChanges = true);
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('삭제 실패: ${e.message}'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasChanges);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.wordbook.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context, _hasChanges);
            },
          ),
        ),
        body: Column(
          children: [
            // --- 검색창 UI ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '단어 또는 뜻으로 검색...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _searchController.clear(),
                  )
                      : null,
                ),
              ),
            ),
            // --- 단어 목록 UI ---
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredWords.isEmpty
                  ? Center(
                child: Text(
                  _searchController.text.isNotEmpty
                      ? '검색 결과가 없습니다.'
                      : '단어장에 추가된 단어가 없습니다.\n아래 버튼으로 단어를 추가해보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              )
                  : RefreshIndicator(
                onRefresh: _loadWords,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 80.0),
                  itemCount: _filteredWords.length,
                  itemBuilder: (context, index) {
                    final wordData = _filteredWords[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 8.0, horizontal: 16.0),
                        leading: IconButton(
                          iconSize: 28,
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            wordData.isMemorized ? Icons.check_circle : Icons
                                .radio_button_unchecked_sharp,
                            color: wordData.isMemorized ? Colors.green : Colors
                                .grey,
                          ),
                          onPressed: () async {
                            // UI를 먼저 업데이트하여 즉각적인 반응을 보여줍니다.
                            setState(() {
                              wordData.isMemorized = !wordData.isMemorized;
                              _hasChanges = true;
                            });
                            try {
                              // 서버에 변경사항을 전송합니다.
                              await _apiService.updateWordMemorizedStatus(
                                wordId: wordData.id,
                                isMemorized: wordData.isMemorized,
                              );
                            } catch (e) {
                              // 실패 시 UI를 원래 상태로 되돌립니다.
                              setState(() =>
                              wordData.isMemorized = !wordData.isMemorized);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text("상태 변경에 실패했습니다.")),
                                );
                              }
                            }
                          },
                        ),
                        title: Text(wordData.word, style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (wordData.pronunciation != null &&
                                  wordData.pronunciation!.isNotEmpty)
                                Text(wordData.pronunciation!, style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontStyle: FontStyle.italic)),
                              const SizedBox(height: 3),
                              Text(wordData.definition,
                                  style: const TextStyle(fontSize: 15)),
                              if (wordData.englishExample != null &&
                                  wordData.englishExample!.isNotEmpty) ...[
                                const Divider(height: 16),
                                Text(wordData.englishExample!, style: TextStyle(
                                    color: Colors.grey.shade800,
                                    fontStyle: FontStyle.italic)),
                              ],
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                wordData.isFavorite ? Icons.star : Icons
                                    .star_border,
                                color: wordData.isFavorite
                                    ? Colors.amber
                                    : Colors.grey,
                              ),
                              onPressed: () async {
                                // UI를 먼저 업데이트합니다.
                                setState(() {
                                  wordData.isFavorite = !wordData.isFavorite;
                                  _hasChanges = true;
                                });
                                try {
                                  // 서버에 변경사항을 전송합니다.
                                  await _apiService.updateWordFavoriteStatus(
                                    wordId: wordData.id,
                                    isFavorite: wordData.isFavorite,
                                  );
                                } catch (e) {
                                  // 실패 시 UI를 되돌립니다.
                                  setState(() =>
                                  wordData.isFavorite = !wordData.isFavorite);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text("즐겨찾기 변경에 실패했습니다.")),
                                    );
                                  }
                                }
                              },
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'delete') {
                                  _showDeleteConfirmDialog(wordData);
                                } else if (value == 'edit') {
                                  // 수정 화면으로 이동하고, 결과가 돌아올 때까지 기다립니다.
                                  final result = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          WordEditScreen(word: wordData),
                                    ),
                                  );
                                  // 수정이 성공적으로 완료되었다면(true 반환), 단어 목록을 새로고침합니다.
                                  if (result == true) {
                                    _loadWords();
                                    setState(() => _hasChanges = true);
                                  }
                                }
                              },
                              itemBuilder: (context) =>
                              [
                                const PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Row(children: [
                                    Icon(Icons.edit_outlined),
                                    SizedBox(width: 8),
                                    Text('수정')
                                  ]),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(children: [
                                    Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('삭제',
                                        style: TextStyle(color: Colors.red))
                                  ]),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            _createSlideRoute(
                              WordDetailPagerScreen(
                                words: _filteredWords,
                                initialIndex: index,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _navigateAndAddWord,
          label: const Text('단어 추가'),
          icon: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class FilteredWordsScreen extends StatefulWidget {
  final String title;
  final String filterStatus;

  const FilteredWordsScreen({
    Key? key,
    required this.title,
    required this.filterStatus,
  }) : super(key: key);

  @override
  State<FilteredWordsScreen> createState() => _FilteredWordsScreenState();
}

class _FilteredWordsScreenState extends State<FilteredWordsScreen> {
  final ApiService _apiService = ApiService();

  // --- 검색 기능을 위한 상태 변수 추가 ---
  final _searchController = TextEditingController();
  List<UserWord> _allWords = [];
  List<UserWord> _filteredWords = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWords();
    _searchController.addListener(_filterWords);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 단어 로딩 함수
  Future<void> _loadWords() async {
    setState(() => _isLoading = true);
    try {
      final status = widget.filterStatus == 'all' ? null : widget.filterStatus;
      final words = await _apiService.getAllWords(status: status)
          .then((data) => data.map((item) => UserWord.fromJson(item)).toList());

      if (mounted) {
        setState(() {
          _allWords = words;
          _filteredWords = words;
          _isLoading = false;
        });
      }
    } catch(e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('단어 로딩 실패: $e')),
        );
      }
    }
  }

  // 단어 필터링 함수
  void _filterWords() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredWords = _allWords.where((word) {
        final wordLower = word.word.toLowerCase();
        final definitionLower = word.definition.toLowerCase();
        return wordLower.contains(query) || definitionLower.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadWords,
          ),
        ],
      ),
      body: Column(
        children: [
          // --- 검색창 UI 추가 ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '단어 또는 뜻으로 검색...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                )
                    : null,
              ),
            ),
          ),
          // --- 단어 목록 UI ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredWords.isEmpty
                ? Center(
              child: Text(
                _searchController.text.isNotEmpty
                    ? '검색 결과가 없습니다.'
                    : '표시할 단어가 없습니다.',
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadWords,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 12.0),
                itemCount: _filteredWords.length, // 필터링된 리스트 사용
                itemBuilder: (context, index) {
                  final wordData = _filteredWords[index]; // 필터링된 리스트 사용
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      title: Text(wordData.word, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(wordData.definition),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          _createSlideRoute(
                            WordDetailPagerScreen(
                              words: _filteredWords, // 현재 필터링된 목록 전체를 전달
                              initialIndex: index,     // 탭한 단어의 순번을 전달
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  _StudyScreenState createState() => _StudyScreenState();
}

// ▼▼▼ [MODIFY] Change the _StudyScreenState class ▼▼▼
class _StudyScreenState extends State<StudyScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_PronunciationPracticeTabState> _pronunciationKey = GlobalKey();
  final GlobalKey<_GrammarPracticeScreenState> _grammarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void refreshCurrentTab() {
    // 현재 선택된 탭 인덱스를 확인
    if (_tabController.index == 0) {
      // '발음 연습' 탭의 새로고침 함수 호출
      _pronunciationKey.currentState?.refresh();
    } else if (_tabController.index == 1) {
      // '문법 연습' 탭의 새로고침 함수 호출
      _grammarKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.mic), text: '발음 학습'),
            Tab(icon: Icon(Icons.menu_book), text: '문법 학습'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              PronunciationPracticeTab(key: _pronunciationKey),
              GrammarPracticeScreen(key: _grammarKey),
            ],
          ),
        ),
      ],
    );
  }
}

class PronunciationPracticeTab extends StatefulWidget {
  const PronunciationPracticeTab({super.key});
  @override
  _PronunciationPracticeTabState createState() => _PronunciationPracticeTabState();
}

class _PronunciationPracticeTabState extends State<PronunciationPracticeTab> with AutomaticKeepAliveClientMixin {
  final ApiService _apiService = ApiService();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  bool _isPlayerReady = false;
  bool _isRecorderReady = false;
  String? _audioPath;

  bool _isLoadingClone = false;
  bool _isLoadingCorrection = false;
  bool _isLoadingAnalysis = false;
  bool _isVoiceCloned = false;

  String? _errorMessage;
  String? _userId = AppState.userId;
  PronunciationAnalysisResult? _analysisResult;
  String? _pronunciationSessionId;
  bool isStarred = false;
  bool isBookmarked = false;

  String _currentSentence = "로딩 중...";
  final Random _random = Random();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 위젯이 완전히 빌드된 후에 권한을 요청하도록 변경
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initRecorderAndPlayer();
      _changeToNextSentence();
    });
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }

  void refresh() {
    // 기존의 '다른 문장' 버튼 로직을 재사용합니다.
    _changeToNextSentence();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('새로운 문장을 불러왔습니다.'), duration: Duration(seconds: 1)),
    );
  }

  void _changeToNextSentence() {
    setState(() {
      if (AppState.sentencePool.isNotEmpty) {
        _currentSentence = AppState.sentencePool[_random.nextInt(AppState.sentencePool.length)];
      } else {
        _currentSentence = "학습할 문장을 불러오지 못했습니다.";
      }
      _analysisResult = null;
      _audioPath = null;
      _errorMessage = null;
      _pronunciationSessionId = null;
    });
  }

  void _handleError(String message) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
        _isLoadingAnalysis = false;
        _isLoadingClone = false;
        _isLoadingCorrection = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _initRecorderAndPlayer() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      setState(() => _errorMessage = '마이크 권한이 필요합니다.');
      return;
    }
    await _recorder.openRecorder();
    await _player.openPlayer();
    setState(() {
      _isRecorderReady = true;
      _isPlayerReady = true;
    });
  }

  Future<void> _toggleRecording() async {
    if (!_isRecorderReady) return;

    if (_recorder.isRecording) {
      final path = await _recorder.stopRecorder();
      setState(() {});

      if (path != null) {
        final audioFile = File(path);
        final fileSize = await audioFile.length();
        print('🎤 녹음된 파일 경로: $path');
        print('💾 녹음된 파일 크기: $fileSize 바이트');
        // [핵심 수정] 녹음 파일의 유효성 검사를 더 강화합니다.
        // 파일 크기 기준을 2KB에서 4KB로 상향 조정하여 짧은 노이즈 등을 필터링합니다.
        if (await audioFile.exists() && await audioFile.length() > 4096) {
          _analyzeAndCloneVoice(path);
        } else {
          // [핵심 수정] 파일이 유효하지 않으면 분석을 시작하지 않고 즉시 오류 메시지를 표시합니다.
          // 이로써 인식되지 않은 음성으로 분석이 진행되는 것을 완벽히 차단합니다.
          _handleError("목소리가 인식되지 않았습니다. 버튼을 누르고 다시 말씀해주세요.");
        }
      }
    } else {
      // 녹음 시작 로직 (이전과 동일)
      final tempDir = await getTemporaryDirectory();
      _audioPath = '${tempDir.path}/user_pronunciation.m4a';
      setState(() {
        _isVoiceCloned = false;
        _analysisResult = null;
        _errorMessage = null;
      });
      await _recorder.startRecorder(toFile: _audioPath, codec: Codec.aacMP4);
      setState(() {});
    }
  }

  Future<void> _playMyRecording() async {
    // 플레이어가 준비되지 않았거나, 재생 중이거나, 녹음 파일 경로가 없으면 아무것도 하지 않음
    if (!_isPlayerReady || _player.isPlaying || _audioPath == null) return;

    try {
      // flutter_sound의 startPlayer를 사용하여 로컬 파일 경로(_audioPath)에서 오디오를 재생
      await _player.startPlayer(
        fromURI: _audioPath!, // '!'를 사용하여 _audioPath가 null이 아님을 보장
        codec: Codec.aacMP4, // 녹음 시 사용한 코덱과 동일하게 설정
        whenFinished: () {
          // 재생이 끝나면 UI를 갱신하여 버튼 상태 등을 업데이트
          if (mounted) setState(() {});
        },
      );
    } catch (e) {
      _handleError("녹음 파일을 재생할 수 없습니다: $e");
    }
  }

  // 분석 및 음성 복제 로직을 별도 함수로 분리
  Future<void> _analyzeAndCloneVoice(String audioPath) async {
    setState(() {
      _isLoadingAnalysis = true;
      _isLoadingClone = true;
      _errorMessage = null;
      _analysisResult = null;
      _pronunciationSessionId = null;
    });

    try {
      // Future.wait를 사용하여 두 작업을 병렬로 실행
      await Future.wait([
        // 1. 발음 분석 및 저장
        _apiService.analyzeAndSavePronunciation(
          audioPath: audioPath,
          targetText: _currentSentence,
        ).then((response) async {
          if (mounted && response['success'] == true) {
            final analysisData = response['data'] as Map<String, dynamic>;
            setState(() {
              _analysisResult = PronunciationAnalysisResult.fromJson(analysisData);
              _pronunciationSessionId = analysisData['session_id'] as String?;
            });
            // 학습 로그 저장
            await _apiService.addLearningLog(logType: 'pronunciation', count: 1);
            await _apiService.logChallengeProgress(logType: 'pronunciation', value: 1);
          } else {
            // [핵심 수정] 서버가 success: false를 반환하면, 여기서 에러를 발생시켜 catch 블록으로 보냅니다.
            throw ApiException(response['error'] ?? '분석에 실패했습니다.');
          }
        }),
        // 2. 음성 복제
        _cloneUserVoice(audioPath),
      ]);

      if(mounted && _errorMessage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 분석 및 음성 등록이 완료되었습니다!')),
        );
      }
    } on ApiException catch (e) {
      // API 서비스에서 발생한 모든 명시적 오류를 여기서 처리합니다.
      _handleError(e.message);
    } catch (e) {
      // 네트워크 오류 등 기타 예외 처리
      _handleError('알 수 없는 오류가 발생했습니다: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAnalysis = false;
          _isLoadingClone = false;
        });
      }
    }
  }

  // 음성 복제 함수
  Future<void> _cloneUserVoice(String path) async {

    print("--- [1/4] _cloneUserVoice 함수 시작됨 ---");

    try {
      const String baseUrl = String.fromEnvironment(
          'AI_BACKEND_URL',
          defaultValue: 'http://10.0.2.2:8000'
      );
      final url = Uri.parse('$baseUrl/api/voice/clone');

      final file = File(path);
      final audioBytes = await file.readAsBytes();
      final base64Audio = base64Encode(audioBytes);

      print("--- [2/4] AI 서버로 음성 등록 요청을 보냅니다... ---");

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': _userId,
          'voice_sample_base64': base64Audio,
        }),
      ).timeout(const Duration(seconds: 45));

      print("--- [3/4] AI 서버 응답 수신 ---");
      print("상태 코드: ${response.statusCode}");
      print("응답 내용: ${utf8.decode(response.bodyBytes)}");

      if (response.statusCode == 200) {
        final responseBody = json.decode(utf8.decode(response.bodyBytes));
        if (responseBody['success']) {
          setState(() => _isVoiceCloned = true);
          print("--- [4/4] 성공: _isVoiceCloned 스위치가 true로 변경됨! ---");
        } else {
          setState(() => _errorMessage = responseBody['error'] ?? '음성 복제에 실패했습니다.');
        }
      } else {
        setState(() => _errorMessage = '음성 복제 실패 (서버 오류: ${response.statusCode})');
      }
    } catch (e) {
      setState(() => _errorMessage = '음성 복제 중 오류 발생: $e');
      print("--- [4/4] 실패: catch 블록에서 오류 발생: $e ---");
    } finally {
      setState(() => _isLoadingClone = false);
    }
  }

  // 교정된 발음 듣기 함수
  Future<void> _getAndPlayCorrection() async {
    if (_pronunciationSessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 발음을 녹음하고 분석을 완료해주세요.')),
      );
      return;
    }
    if (!_isPlayerReady || _player.isPlaying) return;

    setState(() {
      _isLoadingCorrection = true;
      _errorMessage = null;
    });

    try {
      final responseBody = await _apiService.getCorrectedPronunciation(
        sessionId: _pronunciationSessionId!,
        userId: AppState.userId!,
      );

      final responseData = responseBody['data'] as Map<String, dynamic>?;
      if (responseBody['success'] == true && responseData != null) {
        final correctedAudioBase64 = responseData['corrected_audio_base64'] as String?;
        if (correctedAudioBase64 != null && correctedAudioBase64.isNotEmpty) {
          await _playAudioFromBase64(correctedAudioBase64);
        } else {
          _handleError('교정된 음성 데이터를 받지 못했습니다.');
        }
      } else {
        _handleError(responseBody['error']?.toString() ?? '교정된 발음 생성에 실패했습니다.');
      }
    } on ApiException catch (e) {
      _handleError(e.message);
    } catch (e) {
      _handleError('발음 교정 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingCorrection = false);
      }
    }
  }

  // Base64 오디오 재생 함수
  Future<void> _playAudioFromBase64(String base64String) async {
    try {
      Uint8List audioBytes = base64Decode(base64String);
      await _player.startPlayer(
        fromDataBuffer: audioBytes,
        codec: Codec.mp3,
        whenFinished: () {
          if (mounted) setState(() {});
        },
      );
    } catch (e) {
      _handleError("재생 중 오류 발생: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final isRecording = _recorder.isRecording;
    final bool isBusy = _isLoadingClone || _isLoadingCorrection || _isLoadingAnalysis;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 발음 이력 버튼 추가
            Card(
              child: ListTile(
                leading: const Icon(Icons.history, color: Colors.green),
                title: const Text('발음 분석 이력 보기'),
                subtitle: const Text('지금까지의 발음 학습 기록을 확인하세요'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PronunciationHistoryScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // 기존 발음 연습 UI
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black),
              ),
              child: Column(
                children: [
                  Text(
                    _currentSentence,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: isBusy || isRecording ? null : _changeToNextSentence,
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text("다른 문장"),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ▼▼▼ [수정] 버튼 레이아웃을 '녹음'과 '듣기'로 분리하여 개선 ▼▼▼
            // 1. '내 발음 녹음' 버튼
            ElevatedButton.icon(
              onPressed: isBusy ? null : _toggleRecording,
              icon: Icon(isRecording ? Icons.stop : Icons.mic),
              label: Text(
                isRecording ? '녹음 중지' : '내 발음 녹음',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRecording ? Colors.redAccent : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                // 버튼이 화면 전체 너비를 차지하도록 설정
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 12),

            // 2. '내 녹음 듣기'와 '교정 발음 듣기' 버튼을 한 줄에 배치
            Row(
              children: [
                // '내 녹음 듣기' 버튼 (신규 추가)
                Expanded(
                  child: OutlinedButton.icon(
                    // 녹음/분석 중이거나 녹음 파일이 없으면 비활성화
                    onPressed: isBusy || isRecording || _audioPath == null ? null : _playMyRecording,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('내 녹음 듣기'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // '교정 발음 듣기' 버튼 (기존 버튼 수정)
                Expanded(
                  child: OutlinedButton.icon(
                    // 녹음/분석 중이거나 분석 결과(ID)가 없으면 비활성화
                    onPressed: isBusy || isRecording || _pronunciationSessionId == null ? null : _getAndPlayCorrection,
                    icon: const Icon(Icons.volume_up_outlined),
                    label: const Text('교정 발음 듣기'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            // ▲▲▲ [수정] 완료 ▲▲▲

            const SizedBox(height: 16),
            if (_isLoadingAnalysis || _isLoadingClone)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text("음성 분석 및 등록 중...")]),
              ),
            if (_isLoadingCorrection)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text("교정된 발음 생성 중...")]),
              ),
            if (_errorMessage != null && !isBusy && !isRecording)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),

            const SizedBox(height: 24),

            if (_analysisResult != null && !_isLoadingAnalysis)
              _buildAnalysisResultCard(_analysisResult!),

          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisResultCard(PronunciationAnalysisResult result) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("📊 발음 분석 결과", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            Center(
              child: _buildScoreIndicator("종합 점수", result.overallScore, Colors.blue),
            ),
            const SizedBox(height: 24),
            Column(
              children: [
                // 첫 번째 줄: 유창성, 음높이
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildScoreIndicator("유창성", result.fluencyScore, Colors.purple),
                    _buildScoreIndicator("음높이", result.pitchScore, Colors.orange),
                  ],
                ),
                const SizedBox(height: 20), // 줄 사이의 세로 간격
                // 두 번째 줄: 리듬, 강세
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildScoreIndicator("리듬", result.rhythmScore, Colors.green),
                    _buildScoreIndicator("강세", result.stressScore, Colors.red),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildFeedbackSection("상세 피드백", Icons.comment, result.detailedFeedback),
            const SizedBox(height: 16),
            _buildFeedbackSection("개선 제안", Icons.lightbulb, result.suggestions),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreIndicator(String title, double score, Color color) {
    return Column(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: score / 100.0,
                strokeWidth: 8,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
              Center(
                child: Text(
                  score.toStringAsFixed(0),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildFeedbackSection(String title, IconData icon, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.grey.shade700, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 28, bottom: 4),
          child: RichText(
            text: TextSpan(
              // 기본 스타일
              style: const TextStyle(fontSize: 16, color: Colors.black, fontFamily: 'Pretendard', height: 1.4),
              children: buildFeedbackSpans("• $item"), // 👈 1단계에서 만든 공용 함수 호출
            ),
          ),
        )).toList(),
      ],
    );
  }
}


// ▼▼▼ [ADD NEW WIDGET] Add the new grammar practice screen widget ▼▼▼
class GrammarPracticeScreen extends StatefulWidget {
  const GrammarPracticeScreen({super.key});
  @override
  _GrammarPracticeScreenState createState() => _GrammarPracticeScreenState();
}

class _GrammarPracticeScreenState extends State<GrammarPracticeScreen> with AutomaticKeepAliveClientMixin {
  final ApiService _apiService = ApiService();

  // UI 상태를 관리하기 위한 변수들
  bool _isLoading = true;
  String? _sessionId;
  TestQuestion? _currentQuestion; // 레벨 테스트에서 사용했던 문제 모델 재사용
  String? _selectedAnswer;
  String? _errorMessage;
  String _fillBlank(String originalText, String newText) {
    final RegExp blankRegex = RegExp(r'_{1,}');
    return originalText.replaceAll(blankRegex, '**$newText**');
  }

  // 피드백 UI를 제어하기 위한 변수들
  bool _showFeedback = false;
  bool _isCorrect = false;
  String? _explanation;
  TestQuestion? _nextQuestion; // 다음 문제를 미리 받아두기 위한 변수
  int? _currentHistoryId;
  bool _isQuestionFavorite = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  void refresh() {
    // 새로운 문제 세션을 시작하는 함수를 호출합니다.
    _startSession();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('새로운 문제 세션을 시작합니다.'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _toggleFavorite() async {
    if (_currentQuestion == null) return;

    final newStatus = !_isQuestionFavorite;

    setState(() {
      _isQuestionFavorite = newStatus;
    });

    try {
      // [수정] 즐겨찾기 추가 시(newStatus == true), 문제 내용도 함께 보냅니다.
      await _apiService.toggleGrammarQuestionFavorite(
        questionId: _currentQuestion!.id,
        isFavorite: newStatus,
        question: newStatus ? _currentQuestion!.text : null,
        options: newStatus ? _currentQuestion!.options : null,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isQuestionFavorite = !newStatus;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('즐겨찾기 변경에 실패했습니다.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 세션을 시작하고 첫 문제를 받아오는 함수
  Future<void> _startSession() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await _apiService.startGrammarSession(
        language: 'en',
        level: AppState.userLevel ?? 'B1',
      );
      if (mounted && response['success'] == true) {
        setState(() {
          _sessionId = response['session_id'];
          _currentQuestion = TestQuestion.fromJson(response['question']);
          _isQuestionFavorite = _currentQuestion!.isFavorite;
          _isLoading = false;
        });
      } else {
        _handleError(response['error'] ?? '세션을 시작할 수 없습니다.');
      }
    } catch (e) {
      _handleError('서버에 연결할 수 없습니다.');
    }
  }

  // 답변을 제출하고, 채점 결과와 다음 문제를 받아오는 함수
  Future<void> _submitAnswer() async {
    if (_selectedAnswer == null) return;
    setState(() => _isLoading = true);

    try {
      final response = await _apiService.submitGrammarAnswer(
        sessionId: _sessionId!,
        questionId: _currentQuestion!.id,
        answer: _selectedAnswer!,
      );

      if (mounted && response['success'] == true) {
        Map<String, dynamic>? historyResponse;
        _apiService.addLearningLog(logType: 'grammar', count: 1);
        _apiService.logChallengeProgress(logType: 'grammar', value: 1);

        try {
          final String questionTemplate = _currentQuestion!.text;
          final String userAnswerChoice = _currentQuestion!.options[_selectedAnswer]!;
          final String transcribedTextForHistory = _fillBlank(questionTemplate, userAnswerChoice);
          final String correctedTextForHistory = response['corrected_text'] ?? "[정답 정보를 찾을 수 없음]";
          final List<String> grammarFeedback = response['explanation'] != null ? [response['explanation']] : [];

          // [핵심 수정] 서버에서 받은 is_correct 값을 가져옵니다.
          final bool isCorrect = response['is_correct'] ?? false;

          // [핵심 수정] isCorrect 값을 history 저장 API로 넘겨줍니다.
          historyResponse = await _apiService.addGrammarHistory(
            transcribedText: transcribedTextForHistory,
            correctedText: correctedTextForHistory,
            grammarFeedback: grammarFeedback,
            vocabularySuggestions: [],
            isCorrect: response['is_correct'] ?? false,
          );
          print("✅ 객관식 문법 학습 이력이 성공적으로 저장되었습니다. ID: ${historyResponse['id']}");

        } catch (e) {
          print("❌ 문법 학습 이력 저장 실패: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('학습 이력을 저장하는 데 실패했습니다.'), backgroundColor: Colors.orange),
            );
          }
        }

        setState(() {
          _isCorrect = response['is_correct'];
          _explanation = response['explanation'];
          _nextQuestion = TestQuestion.fromJson(response['next_question']);
          _showFeedback = true;
          _isLoading = false;
          if (historyResponse != null) {
            _currentHistoryId = historyResponse['id'];
          }
        });

      } else {
        _handleError(response['error'] ?? '답변 제출에 실패했습니다.');
      }
    } catch (e) {
      _handleError('답변 처리 중 오류가 발생했습니다.');
    }
  }

  // '다음 문제' 버튼을 눌렀을 때 호출되는 함수
  void _loadNextQuestion() {
    setState(() {
      _currentQuestion = _nextQuestion;
      // 👈 3-2. [수정] 다음 문제의 즐겨찾기 상태를 변수에 저장 (에러 해결)
      _isQuestionFavorite = _nextQuestion!.isFavorite;
      // 나머지 상태 초기화
      _nextQuestion = null;
      _selectedAnswer = null;
      _showFeedback = false;
      _currentHistoryId = null;
    });
  }

  // 에러 처리 헬퍼 함수
  void _handleError(String message) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      // Scaffold 배경색을 앱 전체 테마와 맞춤
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _currentQuestion == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }
    if (_currentQuestion == null) {
      return const Center(child: Text('문제를 불러오는 데 실패했습니다.'));
    }

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        // 문법 연습 이력 보기 버튼
        Card(
          child: ListTile(
            leading: const Icon(Icons.history, color: Colors.blue),
            title: const Text('문법 학습 이력 보기'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const GrammarHistoryScreen()));
            },
          ),
        ),
        const SizedBox(height: 24),

        // 문제 카드
        _buildQuestionCard(_currentQuestion!),

        const SizedBox(height: 24),

        // 피드백 카드 (답변 제출 후 표시됨)
        if (_showFeedback)
          _buildFeedbackCard(),

        // 액션 버튼 (상황에 따라 '제출' 또는 '다음 문제' 표시)
        ElevatedButton(
          onPressed: _isLoading
              ? null
              : (_showFeedback ? _loadNextQuestion : _submitAnswer),
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(_showFeedback ? '다음 문제' : '정답 확인'),
        ),
      ],
    );
  }

  // 문제 UI를 만드는 위젯
  Widget _buildQuestionCard(TestQuestion question) {
    final optionKeys = question.options.keys.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('다음 빈칸에 들어갈 가장 알맞은 것을 고르세요.', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    question.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                // 👈 4. [수정] 즐겨찾기 아이콘 버튼 추가
                IconButton(
                  onPressed: _toggleFavorite, // 2번에서 만든 함수 연결
                  icon: Icon(
                    _isQuestionFavorite ? Icons.star : Icons.star_border, // 상태에 따라 아이콘 변경
                    color: _isQuestionFavorite ? Colors.amber : Colors.grey,
                    size: 28,
                  ),
                  tooltip: '즐겨찾기',
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 선택지 목록
            ...optionKeys.map((key) {
              return RadioListTile<String>(
                title: Text(question.options[key]!, style: const TextStyle(fontSize: 16)),
                value: key,
                groupValue: _selectedAnswer,
                // 피드백이 표시되면 더 이상 선택지를 변경할 수 없도록 함
                onChanged: _showFeedback ? null : (value) => setState(() => _selectedAnswer = value),
                activeColor: Colors.green,
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // 피드백 UI를 만드는 위젯
  Widget _buildFeedbackCard() {
    return Card(
      color: _isCorrect ? Colors.green.shade50 : Colors.red.shade50,
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined,
                  color: _isCorrect ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded( // 👈 Expanded로 감싸서 아이콘이 오른쪽 끝으로 가도록 함
                  child: Text(
                    _isCorrect ? '정답입니다!' : '틀렸습니다',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _isCorrect ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            MarkdownBody(
              data: _explanation ?? '해설을 불러올 수 없습니다.',
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 16, height: 1.5, fontFamily: 'Pretendard'),
                strong: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class SituationScreen extends StatefulWidget {
  const SituationScreen({super.key});

  @override
  State<SituationScreen> createState() => _SituationScreenState();
}

class _SituationScreenState extends State<SituationScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ▼▼▼ [수정] 1. API 키와 UI 데이터를 관리하기 위한 Map들을 정의합니다. ▼▼▼
  // 서버로 보낼 API 키 (영어)
  final Map<String, String> _situationApiKeys = {
    '공항': 'airport',
    '식당': 'restaurant',
    '호텔': 'hotel',
    '길거리': 'street',
  };

  // 화면에 표시될 이미지 경로
  final Map<String, String> _situationImagePaths = {
    '공항': 'assets/airport.png',
    '식당': 'assets/restaurant.png',
    '호텔': 'assets/hotel.png',
    '길거리': 'assets/road.png',
  };

  // 이미지가 없을 경우를 대비한 대체 아이콘
  final Map<String, IconData> _situationFallbackIcons = {
    '공항': Icons.flight_takeoff,
    '식당': Icons.restaurant_menu_outlined,
    '호텔': Icons.hotel_outlined,
    '길거리': Icons.signpost_outlined,
  };


  @override
  Widget build(BuildContext context) {
    super.build(context);
    // ▼▼▼ [핵심 추가 1/2] 화면의 전체 너비를 가져옵니다. ▼▼▼
    final screenWidth = MediaQuery
        .of(context)
        .size
        .width;
    // 화면 너비의 특정 비율로 글자 크기를 계산합니다. (값은 조절 가능)
    // clamp를 사용해 글자가 너무 커지거나 작아지는 것을 방지합니다.
    final titleFontSize = (screenWidth / 18).clamp(20.0, 36.0);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            '공부하고 싶은 상황을\n선택해주세요',
            textAlign: TextAlign.center,
            // ▼▼▼ [핵심 추가 2/2] 고정된 크기 대신 계산된 글자 크기를 적용합니다. ▼▼▼
            style: TextStyle(
              fontSize: titleFontSize, // 적용!
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: _situationApiKeys.keys.map((String situationName) {
                final String apiKey = _situationApiKeys[situationName]!;
                final String imagePath = _situationImagePaths[situationName]!;
                final IconData fallbackIcon = _situationFallbackIcons[situationName]!;

                return _buildSituationButton(
                  context,
                  situation: situationName,
                  imagePath: imagePath,
                  fallbackIcon: fallbackIcon,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ConversationScreen(situation: apiKey),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // _buildSituationButton 위젯은 기존 코드와 동일하게 재사용합니다.
  Widget _buildSituationButton(BuildContext context, {
    required String situation,
    String? imagePath,
    IconData? fallbackIcon,
    required VoidCallback onTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 아이콘 크기 계산 (이전과 동일)
        final double iconSize = constraints.maxWidth * 0.5;
        // ▼▼▼ [핵심 추가 1/2] 버튼 너비에 비례하여 글자 크기를 계산합니다. ▼▼▼
        final double buttonFontSize = (constraints.maxWidth / 10).clamp(
            16.0, 24.0);

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (imagePath != null)
                  Image.asset(
                    imagePath,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        fallbackIcon ?? Icons.help_outline,
                        size: iconSize * 0.8,
                        color: Colors.green,
                      );
                    },
                  )
                else
                  Icon(
                    fallbackIcon ?? Icons.help_outline,
                    size: iconSize * 0.8,
                    color: Colors.green,
                  ),
                const SizedBox(height: 12),
                Text(
                  situation,
                  // ▼▼▼ [핵심 추가 2/2] 계산된 글자 크기를 적용합니다. ▼▼▼
                  style: TextStyle(
                    fontSize: buttonFontSize, // 적용!
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ChatMessage {
  final String id; // ✨ 1. 고유 ID 필드 추가
  String conversationText;
  final String speechText;
  final String? educationalText;
  final String? translatedText;
  final bool isUser;
  bool isExpanded;

  ChatMessage({
    required this.id, // ✨ 2. 생성자에 id 추가
    required this.conversationText,
    required this.speechText,
    this.educationalText,
    this.translatedText,
    this.isUser = false,
    this.isExpanded = false,
  });
}

class ConversationScreen extends StatefulWidget {
  final String situation;

  const ConversationScreen({super.key, required this.situation});

  @override
  _ConversationScreenState createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _textController = TextEditingController();
  final String _baseUrl = const String.fromEnvironment(
      'AI_BACKEND_URL',
      defaultValue: 'http://10.0.2.2:8000'
  );
  String? _sessionId;
  bool _isLoading = true;
  bool _isAiTyping = false;
  String _loadingMessage = 'AI와 연결하는 중...';

  final List<ChatMessage> _messages = [];

  FlutterSoundRecorder? _recorder;
  final AudioPlayer _player = AudioPlayer(playerId: 'conversation_player');
  bool _isRecording = false;
  String? _recordingPath;
  String? _currentlyPlayingMessageId;
  late final DateTime _startTime;
  final FlutterTts _flutterTts = FlutterTts();
  final Map<String, String> _situationDisplayNames = {
    'airport': '공항',
    'restaurant': '식당',
    'hotel': '호텔',
    'street': '길거리',
  };

  String _getSituationDisplayName(String apiKey) {
    return _situationDisplayNames[apiKey] ?? apiKey;
  }

  StreamSubscription? _playerStateSubscription;

  // ▼▼▼ [1/4. 언어 코드 변환 함수 추가] ▼▼▼
  String _getLanguageCode() {
    switch (AppState.targetLanguage) {
      case '일본어':
        return 'ja';
      case '중국어':
        return 'zh';
      case '불어':
        return 'fr';
      case '한국어':
        return 'ko';
      case '영어':
      default:
        return 'en';
    }
  }

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _initialize();
    _playerStateSubscription =
        _player.onPlayerStateChanged.listen((PlayerState state) {
          print('[AudioPlayer][Conversation] 상태 변경: $state');
        });
    _player.onLog.listen((String log) {
      print('[AudioPlayer][Conversation] 상세 로그: $log');
    }, onError: (Object e) {
      print('[AudioPlayer][Conversation] 로그 에러: $e');
    });

    // ✨ 1. TTS 완료/취소 리스너 설정
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _currentlyPlayingMessageId = null; // 재생이 끝나면 ID 초기화
        });
      }
    });

    _flutterTts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _currentlyPlayingMessageId = null; // 중지되면 ID 초기화
        });
      }
    });
  }

  Future<void> _initialize() async {
    final micStatus = await Permission.microphone.request();
    if (micStatus != PermissionStatus.granted) {
      setState(() {
        _isLoading = false;
        _loadingMessage = '마이크 권한이 필요합니다.';
      });
      return;
    }
    _recorder = FlutterSoundRecorder();
    await _recorder!.openRecorder();
    _startNewConversation();
  }

  @override
  void dispose() {
    _logConversationDuration();

    _recorder?.closeRecorder();
    _recorder = null;

    // 👇 3단계: dispose가 호출될 때 리스너를 취소(cancel)합니다.
    _playerStateSubscription?.cancel();
    _player.dispose();

    _textController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _logConversationDuration() async {
    final ApiService apiService = ApiService();
    try {
      // 화면에 머무른 시간을 초 단위로 계산
      final durationInSeconds = DateTime
          .now()
          .difference(_startTime)
          .inSeconds;

      // 10초 미만은 기록하지 않음 (실수로 들어왔다 나간 경우 등)
      if (durationInSeconds < 10) {
        print("학습 시간이 너무 짧아 기록하지 않습니다.");
        return;
      }

      // 초를 분 단위로 변환 (올림 처리)
      final durationInMinutes = (durationInSeconds / 60).ceil();

      await apiService.addLearningLog(
        logType: 'conversation',
        duration: durationInMinutes,
      );
      await apiService.logChallengeProgress(
          logType: 'conversation',
          value: durationInMinutes
      );

      print("✅ 회화 학습 로그 ($durationInMinutes 분) 저장 성공!");
    } catch (e) {
      print("❌ 회화 학습 로그 저장 실패: $e");
    }
  }

  Future<void> _togglePlayback(ChatMessage message) async {
    final bool isCurrentlyPlaying = _currentlyPlayingMessageId == message.id;

    await _flutterTts.stop();

    if (isCurrentlyPlaying) {
      setState(() {
        _currentlyPlayingMessageId = null;
      });
    } else {
      setState(() {
        _currentlyPlayingMessageId = message.id;
      });

      // ✨👇 [핵심 수정] 빠져있던 언어 및 속도 설정 코드를 다시 추가합니다.
      await _flutterTts.setLanguage("en-US"); // 👈 원어민 목소리를 위한 언어 설정
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      // ✨👆 여기까지 추가

      await _flutterTts.speak(message.speechText);
    }
  }

  // 👈 3. AI 응답 텍스트를 파싱하여 _messages 리스트에 추가하는 헬퍼 함수
  void _addAiResponseMessage(Map<String, dynamic> data) {
    // 이 부분의 변수 선언은 그대로 둡니다.
    String conversationTextForDisplay;
    String speechTextForTts;
    String? educationalText;
    final String? translatedText = data['translated_text'] as String?;

    // AI의 첫 메시지인지 확인 ('speech_text' 필드 존재 여부로 판단)
    if (data.containsKey('speech_text') && data['speech_text'] != null) {
      conversationTextForDisplay = data['ai_message'] as String;
      speechTextForTts = data['speech_text'] as String;
      educationalText = null;
    }
    // 이후의 메시지 처리
    else {
      const separator = '\n\n======== Recommended ========\n\n';
      final fullResponseText = data['ai_message'] as String;
      final parts = fullResponseText.split(separator);

      speechTextForTts = parts[0].trim();
      conversationTextForDisplay = speechTextForTts;

      educationalText = parts.length > 1 ? parts[1].trim() : null;
    }

    // ✨ 아래 setState 부분을 교체해주세요.
    setState(() {
      _messages.add(ChatMessage(
        id: const Uuid().v4(),
        // 변수 이름을 올바르게 전달합니다.
        conversationText: conversationTextForDisplay,
        speechText: speechTextForTts,
        educationalText: educationalText,
        translatedText: translatedText,
        isUser: false,
      ));
    });
  }

  Future<void> _startNewConversation() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/conversation/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'flutter_user_01',
          'situation': widget.situation,
          'difficulty': 'beginner',
          'language': _getLanguageCode(),
          'mode': 'auto',
          'translate': AppState.beginnerMode,
        }),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body['success']) {
          final data = body['data'];
          _sessionId = data['session_id'];

          // [핵심 수정]
          // 첫 메시지 처리도 다른 AI 응답과 마찬가지로
          // _addAiResponseMessage 함수에 맡깁니다.
          _addAiResponseMessage(data);

        } else {
          _handleError(body['error'] ?? '대화 시작에 실패했습니다.');
        }
      } else {
        _handleError('서버에 연결할 수 없습니다. (코드: ${response.statusCode})');
      }
    } catch (e) {
      _handleError('네트워크 오류가 발생했습니다: $e');
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendVoiceMessage(String path) async {
    if (_sessionId == null) return;

    // 사용자의 음성 메시지 말풍선을 식별할 수 있도록 변수에 저장
    final userMessageBubble = ChatMessage(
        id: const Uuid().v4(), // ✨ 고유 ID 생성
        conversationText: '🎤 (음성 메시지 전송 중...)',
        speechText: '음성 메시지 전송 중',
        isUser: true);

    setState(() {
      _isLoading = true; // 로딩 상태는 SnackBar와 하단 입력창 제어에만 사용
      _loadingMessage = '음성을 분석하는 중...';
      _messages.add(userMessageBubble);
      _isAiTyping = true;
    });

    final bool beginnerMode = AppState.beginnerMode;

    try {
      final audioBytes = await File(path).readAsBytes();
      final audioBase64 = base64Encode(audioBytes);

      final response = await http.post(
        Uri.parse('$_baseUrl/api/conversation/voice'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': _sessionId,
          'audio_base64': audioBase64,
          'language': _getLanguageCode(),
          'translate': beginnerMode,
        }),
      );

      final responseBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200 && responseBody['success'] == true) {
        // [성공 시]
        final data = responseBody['data'];
        setState(() {
          userMessageBubble.conversationText =
          '🗣️ "${data['recognized_text']}"';
        });
        _addAiResponseMessage(data);
      } else {
        // [실패 시]
        // 백엔드에서 전달된 오류 메시지를 가져옴
        final errorMessageFromServer = responseBody['error'] ??
            '알 수 없는 오류가 발생했습니다.';

        // [핵심 수정 1/2] 말풍선에는 짧은 메시지를 표시
        setState(() {
          userMessageBubble.conversationText = '⚠️ 목소리를 인식할 수 없습니다.';
        });

        // [핵심 수정 2/2] 하단 SnackBar에는 서버에서 받은 상세한 메시지를 표시
        _handleError(errorMessageFromServer);
      }
    } catch (e) {
      // [네트워크 오류 등 예외 발생 시]
      setState(() {
        userMessageBubble.conversationText = '⚠️ 목소리를 인식할 수 없습니다.';
      });
      _handleError('네트워크에 연결할 수 없습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAiTyping = false;
        });
      }
    }
  }

  Future<void> _sendTextMessage() async {
    if (_textController.text.isEmpty || _sessionId == null) return;
    final userMessageText = _textController.text;
    _textController.clear();

    setState(() {
      _isLoading = true;
      _loadingMessage = 'AI가 답변을 생각하는 중...';
      _messages.add(ChatMessage(
          id: const Uuid().v4(), // ✨ 고유 ID 생성
          conversationText: '🗣️ "$userMessageText"',
          speechText: userMessageText,
          isUser: true));
      _isAiTyping = true;
    });

    // Hive 대신 AppState에서 초보자 모드 설정값을 직접 가져옵니다.
    final bool beginnerMode = AppState.beginnerMode;

    try {
      final response = await http.post(
          Uri.parse('$_baseUrl/api/conversation/text'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'session_id': _sessionId!,
            'message': userMessageText,
            'language': _getLanguageCode(),
            'translate': beginnerMode, // 번역 요청 플래그
          })
      );
      if (response.statusCode == 200) {
        final responseBody = json.decode(utf8.decode(response.bodyBytes));
        if (responseBody['success']) {
          final data = responseBody['data'];
          _addAiResponseMessage(data);
        } else {
          _handleError(responseBody['error'] ?? '메시지 처리에 실패했습니다.');
        }
      } else {
        _handleError('서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      _handleError('메시지 전송 중 오류 발생: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _isAiTyping = false;
      });
    }
  }

  Future<void> _startRecording() async {
    Directory tempDir = await getTemporaryDirectory();
    _recordingPath = '${tempDir.path}/flutter_sound.m4a';
    await _recorder!.startRecorder(toFile: _recordingPath, codec: Codec.aacMP4);
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    await _recorder!.stopRecorder();
    setState(() => _isRecording = false);
    if (_recordingPath != null) {
      _sendVoiceMessage(_recordingPath!);
    }
  }

  void _handleError(String message) {
    setState(() {
      _isLoading = false;
      _loadingMessage = message; // 로딩 메시지에도 에러 표시
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // "서버 오류: " 같은 접두사 대신, 받은 메시지를 그대로 보여줌
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String characterImage = 'assets/fox.png';
    final targetLanguageName = AppState.targetLanguage ?? '학습 언어';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        title: const Text('회화 학습'),
        backgroundColor: const Color(0xFFF3F4F8),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(
                vertical: 16.0, horizontal: 16.0),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              '#${widget.situation}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800),
            ),
          ),
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_loadingMessage)
              ],
            ))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16.0, vertical: 16.0),
              itemCount: _messages.length + (_isAiTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return _buildAiTypingIndicator(); // 새 위젯 호출
                }
                final message = _messages[index];
                // 👈 4. ListView 빌드 로직을 새 데이터 모델에 맞게 수정
                if (message.isUser) {
                  return _buildUserMessageBubble(message);
                } else {
                  // AI 메시지는 대화 말풍선과 교육 박스를 Column으로 묶어서 표시
                  return Column(
                    children: [
                      _buildAiMessageBubble(message),
                      if (message.educationalText != null)
                        _buildEducationalBox(message, index), // 👈 새 위젯 호출
                    ],
                  );
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                )
              ],
            ),
            child: SafeArea(
              child: Column( // Column으로 감싸서 안내 문구를 추가할 공간 확보
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: InputDecoration(
                            hintText: '메시지를 입력하세요...',
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30.0),
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20.0, vertical: 10.0),
                          ),
                          onSubmitted: (_) => _sendTextMessage(),
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      IconButton(
                        icon: Icon(_isRecording ? Icons.stop : Icons.mic,
                            color: _isRecording ? Colors.red.shade700 : Colors
                                .green.shade800),
                        onPressed: _isLoading ? null : (_isRecording
                            ? _stopRecording
                            : _startRecording),
                        style: IconButton.styleFrom(
                          backgroundColor: _isRecording
                              ? Colors.red.shade100
                              : Colors.green.shade100,
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.send, color: Colors.green.shade800),
                        onPressed: _isLoading ? null : _sendTextMessage,
                      ),
                    ],
                  ),
                  // [핵심 추가] 학습 언어가 한국어가 아닐 때만 안내 문구 표시
                  if (AppState.targetLanguage != '한국어')
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0, right: 80),
                      // 아이콘 영역만큼 오른쪽 여백
                      child: Text(
                        '음성 입력은 $targetLanguageName로만 가능해요.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  // 👈 5. 말풍선 위젯들을 역할에 맞게 3개로 분리/수정
  Widget _buildUserMessageBubble(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(message.conversationText, style: const TextStyle(
                fontSize: 15, color: Colors.black87, height: 1.4)),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: AssetImage(AppState.selectedCharacterImage),
          ),
        ],
      ),
    );
  }

  Widget _buildAiTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, color: Colors.green.shade700, size: 24),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: const SizedBox(
              width: 50, // 점 3개가 들어갈 정도의 너비
              height: 21, // 텍스트 높이와 유사하게
              child:
              // 간단한 로딩 애니메이션 (점 3개가 깜빡이는 효과)
              TypingIndicator(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiMessageBubble(ChatMessage message) {
    final bool isPlaying = _currentlyPlayingMessageId == message.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, color: Colors.green.shade700, size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 원문 + 음성 재생 버튼
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          message.conversationText,
                          style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                              height: 1.4
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        // ✨ 1. 상태에 따라 아이콘 변경
                        icon: Icon(
                          isPlaying ? Icons.stop_circle_outlined : Icons.volume_up,
                          color: Colors.green.shade600,
                          size: 22,
                        ),
                        // ✨ 2. onPressed에 새로 만든 토글 함수 연결
                        onPressed: () => _togglePlayback(message),
                        splashRadius: 20,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      )
                    ],
                  ),

                  // 2. 번역문이 있을 경우에만 구분선과 번역 텍스트를 표시
                  if (message.translatedText != null &&
                      message.translatedText!.isNotEmpty) ...[
                    // 구분선
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      height: 1,
                      color: Colors.black.withOpacity(0.1),
                    ),
                    // 번역 텍스트
                    Text(
                      message.translatedText!,
                      style: TextStyle(
                        fontSize: 14, // 원문보다 약간 작게
                        color: Colors.black.withOpacity(0.6), // 원문보다 연한 색상
                        fontStyle: FontStyle.italic, // 이탤릭체로 구분
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEducationalBox(ChatMessage message, int index) {
    // 1. JSON 파싱을 위한 변수들 선언
    Map<String, dynamic> decodedJson = {};
    String? situationFeedback;
    String? grammarFeedback;
    List<dynamic>? recommendedExpressions;
    String? suggestedSituation;
    String? situationDisplayName;

    // AI가 보낸 피드백이 JSON 형식인지 파싱
    try {
      // educationalText가 null이 아니라고 확신하고 파싱 시도
      decodedJson =
      jsonDecode(message.educationalText!) as Map<String, dynamic>;

      // 2. 각 키에 해당하는 데이터를 변수에 저장
      situationFeedback = decodedJson['상황 피드백'] as String?;
      grammarFeedback = decodedJson['문법 피드백'] as String?;
      recommendedExpressions = decodedJson['추천 표현'] as List<dynamic>?;
      suggestedSituation = decodedJson['추천 상황'] as String?;

      if (suggestedSituation != null && suggestedSituation!.isNotEmpty) {
        situationDisplayName = _getSituationDisplayName(suggestedSituation!);
      }
    } catch (e) {
      // JSON 파싱에 실패하면 피드백 박스를 표시하지 않음
      print("피드백(JSON) 파싱 실패: $e");
      return const SizedBox.shrink();
    }

    // 3. UI 빌드 로직 시작 (기존 구조 활용)
    return Container(
      margin: const EdgeInsets.only(left: 32, bottom: 16),
      child: InkWell(
        onTap: () {
          setState(() {
            _messages[index].isExpanded = !_messages[index].isExpanded;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1), // 연한 노란색 배경
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.amber.shade700,
                      size: 20),
                  const SizedBox(width: 8),
                  const Text("Recommended",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Icon(
                    message.isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: Container(), // 접혔을 때는 아무것도 표시하지 않음
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 20),

                    // --- [핵심 수정] 조건에 따라 라벨과 내용을 동적으로 표시 ---

                    // 4. "상황 피드백"이 있을 경우 표시
                    if (situationFeedback != null &&
                        situationFeedback.isNotEmpty) ...[
                      const Text("💡 상황 피드백", style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.orange)),
                      const SizedBox(height: 8),
                      Text(
                        situationFeedback,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black87, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 5. "문법 피드백"이 있을 경우 표시
                    if (grammarFeedback != null &&
                        grammarFeedback.isNotEmpty) ...[
                      const Text("✍️ 문법 피드백", style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 8),
                      Text(
                        grammarFeedback,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black87, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 6. "추천 표현"이 있을 경우 목록 형태로 표시
                    if (recommendedExpressions != null &&
                        recommendedExpressions.isNotEmpty) ...[
                      const Text("👍 추천 표현", style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green)),
                      const SizedBox(height: 8),
                      for (var expression in recommendedExpressions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text("• $expression", style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                              height: 1.5)),
                        ),
                    ],

                    // --- [수정 완료] ---

                    // 추천 상황으로 이동하는 버튼 (기존 로직 유지)
                    if (suggestedSituation != null &&
                        situationDisplayName != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ConversationScreen(
                                        situation: suggestedSituation!),
                              ),
                            );
                          },
                          icon: const Icon(Icons.swap_horiz),
                          label: Text("'$situationDisplayName' 대화로 이동하기"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: BorderSide(
                                color: Colors.green.withOpacity(0.5)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                crossFadeState: message.isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 커뮤니티 화면
class CommunityScreen extends StatefulWidget {
  final TabController tabController;
  const CommunityScreen({Key? key, required this.tabController}) : super(key: key);

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  // 각 탭의 PostList 상태를 제어하기 위한 키
  final List<GlobalKey<_PostListState>> _postListKeys = List.generate(3, (_) => GlobalKey());
  // StudyGroupListScreen 상태를 제어하기 위한 키
  final GlobalKey<_StudyGroupListScreenState> _studyGroupListKey = GlobalKey();

  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();

    // 검색창 입력을 감지하여 자동으로 검색을 실행 (디바운싱 적용)
    _searchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (_searchQuery != _searchController.text) {
          setState(() {
            _searchQuery = _searchController.text;
          });
          _performSearch();
        }
      });
    });

    // 탭 변경을 감지하여 플로팅 버튼을 다시 그리도록 리스너 추가
    widget.tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    // initState에서 추가한 리스너를 dispose에서 제거합니다.
    widget.tabController.removeListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    super.dispose();
  }

  // '글 작성' 버튼 클릭 시 호출되는 함수
  void _navigateAndCreatePost() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PostWriteScreen()),
    );
    // 글 작성 완료 후, 현재 보고있는 탭의 목록을 새로고침
    if (result == true && mounted) {
      _performSearch();
    }
  }

  // 검색을 실행하는 함수
  void _performSearch() {
    // 현재는 게시판 탭에서만 검색 기능이 동작합니다.
    final currentTabIndex = widget.tabController.index;
    if (currentTabIndex < 3) { // 0, 1, 2번 탭(게시판)일 경우
      _postListKeys[currentTabIndex].currentState?.refreshPosts(searchQuery: _searchQuery);
    }
  }

  // << [수정] 현재 탭에 따라 다른 플로팅 버튼을 보여주는 함수 >>
  Widget? _buildFloatingActionButton() {
    final isStudyGroupTab = widget.tabController.index == 3;

    if (isStudyGroupTab) {
      // '스터디모집' 탭일 경우: '그룹 만들기' 버튼만 표시
      return FloatingActionButton.extended(
        heroTag: 'create_group',
        onPressed: () {
          // '그룹 만들기' 화면으로 이동 후, 그룹이 생성되면 목록 새로고침
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const StudyGroupCreateScreen()),
          ).then((wasCreated) {
            if (wasCreated == true) {
              _studyGroupListKey.currentState?.refreshGroups();
            }
          });
        },
        icon: const Icon(Icons.add),
        label: const Text('그룹 만들기'),
        // backgroundColor를 지정하지 않으면 Theme의 기본 색상을 따라갑니다.
      );
    } else {
      // '자유게시판', '질문게시판', '정보공유' 탭일 경우: '글 작성' 버튼만 표시
      return FloatingActionButton.extended(
        heroTag: 'create_post',
        onPressed: _navigateAndCreatePost,
        label: const Text('글 작성'),
        icon: const Icon(Icons.edit_outlined),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabChildren = [
      PostList(key: _postListKeys[0], category: '자유게시판'),
      PostList(key: _postListKeys[1], category: '질문게시판'),
      PostList(key: _postListKeys[2], category: '정보공유'),
      StudyGroupListScreen(key: _studyGroupListKey),
    ];

    return Scaffold(
      body: Column(
        children: [
          // '스터디모집' 탭에서는 검색창 숨기기
          if (widget.tabController.index != 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '게시글 검색 (제목 + 내용)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                    },
                  )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: (value) => _performSearch(),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: widget.tabController,
              children: tabChildren,
            ),
          ),
        ],
      ),
      // << [수정] 위에서 만든 함수를 사용하여 플로팅 버튼 표시 >>
      floatingActionButton: _buildFloatingActionButton(),
    );
  }
}

// ▼▼▼ [추가] 카테고리별 게시글 목록을 보여주는 별도의 위젯 ▼▼▼
class PostList extends StatefulWidget {
  final String category;
  const PostList({Key? key, required this.category}) : super(key: key);

  @override
  State<PostList> createState() => _PostListState();
}

class _PostListState extends State<PostList> {
  final ApiService _apiService = ApiService();
  late Future<List<Post>> _postsFuture;

  @override
  void initState() {
    super.initState();
    // 위젯이 처음 생성될 때는 검색어 없이 게시글을 불러옵니다.
    _postsFuture = _loadPosts(null);
  }

  // << [수정] Future<List<Post>>를 반환하도록 하고, searchQuery를 받도록 수정 >>
  Future<List<Post>> _loadPosts(String? searchQuery) async {
    final data = await _apiService.getPosts(widget.category, searchQuery: searchQuery);
    return data.map((item) => Post.fromJson(item)).toList();
  }

  // << [수정] 외부(CommunityScreen)에서 호출할 수 있도록 하고, searchQuery 파라미터를 받도록 수정 >>
  void refreshPosts({String? searchQuery}) {
    setState(() {
      _postsFuture = _loadPosts(searchQuery);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Post>>(
      future: _postsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('게시글이 없습니다.'));
        }

        final posts = snapshot.data!;

        // 검색 결과가 없을 때 별도의 메시지를 보여주기 위한 UI 개선
        if (posts.isEmpty) {
          return const Center(child: Text('검색 결과가 없습니다.'));
        }

        return RefreshIndicator(
          onRefresh: () async {
            // 당겨서 새로고침 시에는 현재 검색어를 유지하지 않고 초기화합니다.
            // 만약 검색어를 유지하고 싶다면 refreshPosts(searchQuery: _currentSearchQuery) 형태로 호출해야 합니다.
            refreshPosts();
          },
          child: ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${post.userName} · ${post.createdAt.toLocal().toString().substring(0, 10)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis
                  ),
                  onTap: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (context) => PostDetailPage(post: post)),
                    );

                    if (result == true) {
                      refreshPosts();
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// 글 작성 화면 (오류 수정 및 디자인 통일) -> 이 클래스 전체를 아래 코드로 교체하세요.
class PostWriteScreen extends StatefulWidget {
  const PostWriteScreen({super.key});

  @override
  State<PostWriteScreen> createState() => _PostWritePageState();
}

class _PostWritePageState extends State<PostWriteScreen> {
  final ApiService _apiService = ApiService();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isLoading = false;

  final List<String> _categories = ['자유게시판', '질문게시판', '정보공유', '스터디모집'];
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = _categories.first;
  }

  Future<void> _submitPost() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 모두 입력해주세요.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _apiService.createPost(
        title: _titleController.text,
        content: _contentController.text,
        category: _selectedCategory,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시글이 성공적으로 등록되었습니다!')),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('새 게시글 작성'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submitPost,
            child: _isLoading ? const CircularProgressIndicator() : const Text('등록'),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              items: _categories.map((String category) {
                return DropdownMenuItem<String>(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) setState(() => _selectedCategory = newValue);
              },
              decoration: const InputDecoration(labelText: '카테고리 선택'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '제목'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _contentController,
                decoration: const InputDecoration(labelText: '내용', alignLabelWithHint: true),
                maxLines: null,
                expands: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 게시글 상세 보기 화면 (라벨 및 테마 수정) ---
class PostDetailPage extends StatefulWidget {
  final Post post;
  const PostDetailPage({super.key, required this.post});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final ApiService _apiService = ApiService();
  final _commentController = TextEditingController();
  late Future<List<Comment>> _commentsFuture;
  bool _isLoadingCommentAction = false; // 댓글 관련 액션 로딩 상태

  @override
  void initState() {
    super.initState();
    _commentsFuture = _loadComments();
  }

  Future<List<Comment>> _loadComments() async {
    final data = await _apiService.getComments(widget.post.id);
    return data.map((item) => Comment.fromJson(item)).toList();
  }

  // ▼▼▼ [수정] 댓글 등록 후 목록을 새로고침하는 로직 추가 ▼▼▼
  Future<void> _addComment() async {
    if (_commentController.text.isEmpty || _isLoadingCommentAction) return;

    setState(() => _isLoadingCommentAction = true);

    try {
      await _apiService.createComment(
        postId: widget.post.id,
        content: _commentController.text,
      );
      _commentController.clear();
      FocusScope.of(context).unfocus();
      // 성공 시, 댓글 목록을 다시 불러와 화면을 갱신
      setState(() {
        _commentsFuture = _loadComments();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글이 작성되었습니다.')),
      );
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoadingCommentAction = false);
    }
  }

  // ▼▼▼ [신규] 댓글 삭제 확인 다이얼로그 및 API 호출 함수 ▼▼▼
  Future<void> _deleteComment(Comment comment) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('정말로 이 댓글을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiService.deleteComment(commentId: comment.id);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('댓글이 삭제되었습니다.')));
        setState(() {
          _commentsFuture = _loadComments(); // 목록 새로고침
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  // ▼▼▼ [신규] 댓글 수정 다이얼로그 및 API 호출 함수 ▼▼▼
  Future<void> _showEditCommentDialog(Comment comment) async {
    final textController = TextEditingController(text: comment.content);
    final bool? success = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('댓글 수정'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              if (textController.text.isEmpty) return;
              try {
                await _apiService.updateComment(
                  commentId: comment.id,
                  content: textController.text,
                );
                Navigator.pop(context, true); // 성공 시 true 반환
              } catch (e) {
                if(mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('수정 실패: $e'), backgroundColor: Colors.red));
                }
                Navigator.pop(context, false);
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (success == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('댓글이 수정되었습니다.')));
      setState(() {
        _commentsFuture = _loadComments(); // 목록 새로고침
      });
    }
  }


  Future<void> _deletePost() async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('정말로 이 게시글을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiService.deletePost(postId: widget.post.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('게시글이 삭제되었습니다.')));
          Navigator.pop(context, true); // 삭제 성공 시 true를 반환
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAuthor = widget.post.userId == AppState.userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.post.category),
        actions: [
          if (isAuthor)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => PostEditScreen(post: widget.post)),
                  );
                  if (result == true && mounted) {
                    Navigator.pop(context, true);
                  }
                } else if (value == 'delete') {
                  _deletePost();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, color: Colors.black), SizedBox(width: 8), Text('수정')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red), SizedBox(width: 8), Text('삭제', style: TextStyle(color: Colors.red))])),
              ],
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.post.title, style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text('작성자: ${widget.post.userName}', style: TextStyle(color: Colors.grey.shade600)),
                        const Divider(height: 32),
                        Text(widget.post.content, style: const TextStyle(fontSize: 16, height: 1.5)),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                  child: Text('댓글', style: Theme.of(context).textTheme.titleMedium),
                )),
                FutureBuilder<List<Comment>>(
                  future: _commentsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SliverToBoxAdapter(child: Center(child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(),
                      )));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const SliverToBoxAdapter(child: Center(child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text('아직 댓글이 없습니다.'),
                      )));
                    }
                    final comments = snapshot.data!;
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          final comment = comments[index];
                          final bool isCommentAuthor = comment.userId == AppState.userId;
                          return ListTile(
                            leading: const Icon(Icons.account_circle_outlined, size: 36),
                            title: Text(comment.userName),
                            subtitle: Text(comment.content),
                            // ▼▼▼ [신규] 본인 댓글일 경우 수정/삭제 메뉴 버튼 표시 ▼▼▼
                            trailing: isCommentAuthor
                                ? PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showEditCommentDialog(comment);
                                } else if (value == 'delete') {
                                  _deleteComment(comment);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Text('수정')),
                                const PopupMenuItem(value: 'delete', child: Text('삭제', style: TextStyle(color: Colors.red))),
                              ],
                            )
                                : null,
                          );
                        },
                        childCount: comments.length,
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)), // 입력창에 가려지지 않도록 여백 추가
              ],
            ),
          ),
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: '댓글을 입력하세요...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          // 댓글 전송 중일 때는 로딩 인디케이터 표시
          _isLoadingCommentAction
              ? const Padding(
            padding: EdgeInsets.all(12.0),
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          )
              : IconButton(
            icon: const Icon(Icons.send),
            onPressed: _addComment,
          ),
        ],
      ),
    );
  }
}

// 피드백 화면 클래스
class FeedbackScreen extends StatefulWidget {
  @override
  _FeedbackScreenState createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  TextEditingController _titleController = TextEditingController();
  TextEditingController _contentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    // ▼▼▼ [수정] 배경색을 앱 테마와 통일 ▼▼▼
    return Scaffold(
      backgroundColor: Color(0xFFF3F4F8),
      appBar: AppBar(
        title: Text('피드백 작성'),
        // ▼▼▼ [수정] AppBar 배경색도 통일 ▼▼▼
        backgroundColor: Color(0xFFF3F4F8),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // ▼▼▼ [수정] 제목 입력창 스타일을 앱 테마와 통일 ▼▼▼
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: '제목을 입력해주세요.',
                // InputDecoration 스타일은 앱 전체 테마(MyApp)에서 적용됨
              ),
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),

            // 내용 입력창
            Expanded(
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: '소중한 의견을 남겨주세요.',
                  alignLabelWithHint: true, // hintText가 위로 정렬되도록 함
                ),
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
            SizedBox(height: 24),

            // ▼▼▼ [수정] 등록 버튼 스타일을 앱 테마와 통일 ▼▼▼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // onPressed 로직은 변경 없음
                onPressed: () {
                  if (_titleController.text.trim().isNotEmpty &&
                      _contentController.text.trim().isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('피드백이 성공적으로 제출되었습니다.'),
                        // backgroundColor는 SnackBarTheme으로 관리하거나 직접 지정
                      ),
                    );
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('제목과 내용을 모두 입력해주세요.'),
                        backgroundColor: Colors.red.shade600,
                      ),
                    );
                  }
                },
                child: Text('등록'),
                // ElevatedButton 스타일은 앱 전체 테마(MyApp)에서 자동으로 적용됨
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}

// 알림 설정 화면 클래스
class NotificationSettingsScreen extends StatefulWidget {
  @override
  _NotificationSettingsScreenState createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final ApiService _apiService = ApiService();
  late Future<Map<String, dynamic>> _settingsFuture;

  @override
  void initState() {
    super.initState();
    // 화면이 시작될 때 서버에서 현재 설정값을 불러옵니다.
    _settingsFuture = _apiService.getNotificationSettings();
  }

  // 스위치 값을 변경하고 서버에 업데이트를 요청하는 함수
  Future<void> _updateSetting(String key, bool value, Function(Map<String, dynamic>) updateState) async {
    // 1. UI를 먼저 낙관적으로 업데이트하여 즉각적인 반응을 보여줍니다.
    final currentState = await _settingsFuture;
    final originalValue = currentState[key];
    setState(() {
      currentState[key] = value;
      // Future를 새로고침하여 UI를 다시 그리도록 합니다.
      _settingsFuture = Future.value(currentState);
    });

    try {
      // 2. 서버에 변경된 값을 전송합니다.
      await _apiService.updateNotificationSettings({key: value});
    } catch (e) {
      // 3. 만약 API 호출이 실패하면 UI를 원래 상태로 되돌리고 에러 메시지를 보여줍니다.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정 변경 실패: $e'), backgroundColor: Colors.red),
        );
        setState(() {
          currentState[key] = originalValue;
          _settingsFuture = Future.value(currentState);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF3F4F8),
      appBar: AppBar(
        title: Text('알림 설정'),
        backgroundColor: Color(0xFFF3F4F8),
      ),
      // FutureBuilder를 사용하여 API 로딩 상태를 관리합니다.
      body: FutureBuilder<Map<String, dynamic>>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          // 로딩 중일 때
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // 에러가 발생했을 때
          if (snapshot.hasError) {
            return Center(child: Text('설정을 불러오는 데 실패했습니다: ${snapshot.error}'));
          }
          // 데이터 로딩이 성공했을 때
          final settings = snapshot.data!;
          final studyNotification = settings['study_notification'] ?? true;
          final marketingNotification = settings['marketing_notification'] ?? true;

          return Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _buildNotificationItem(
                        imagePath: 'assets/study.png',
                        fallbackIcon: Icons.school_outlined,
                        title: '공부 알림',
                        subtitle: '시작, 현황, 복습 알림',
                        value: studyNotification,
                        onChanged: (value) {
                          // 'study_notification' 키와 변경된 값을 서버로 전송
                          _updateSetting('study_notification', value, (newState) {
                            setState(() {
                              _settingsFuture = Future.value(newState);
                            });
                          });
                        },
                      ),
                      Divider(height: 1, indent: 16, endIndent: 16),
                      _buildNotificationItem(
                        imagePath: 'assets/bookmark.png',
                        fallbackIcon: Icons.card_giftcard_outlined,
                        title: '혜택 (광고성) 알림',
                        subtitle: null,
                        value: marketingNotification,
                        onChanged: (value) {
                          // 'marketing_notification' 키와 변경된 값을 서버로 전송
                          _updateSetting('marketing_notification', value, (newState) {
                            setState(() {
                              _settingsFuture = Future.value(newState);
                            });
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationItem({
    required String imagePath,
    required IconData fallbackIcon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    // Container를 ListTile로 변경하여 더 깔끔한 UI 구성
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: Image.asset(
        imagePath,
        width: 32,
        height: 32,
        errorBuilder: (context, error, stackTrace) {
          // ▼▼▼ [수정] 아이콘 색상을 테마에 맞게 변경 ▼▼▼
          return Icon(fallbackIcon, size: 30, color: Colors.green);
        },
      ),
      title: Text(
        title,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: Colors.grey.shade600))
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        // ▼▼▼ [수정] Switch 색상을 테마에 맞게 변경 ▼▼▼
        activeColor: Colors.white,
        activeTrackColor: Colors.green,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: Colors.grey.shade400,
      ),
    );
  }
}

// 자주 찾는 질문(FAQ) 화면 클래스
class FAQScreen extends StatefulWidget {
  @override
  _FAQScreenState createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<FAQ>> _faqsFuture;
  Map<int, bool> expandedStates = {};

  @override
  void initState() {
    super.initState();
    _loadFAQs();
  }

  void _loadFAQs() {
    setState(() {
      _faqsFuture = _apiService.getFAQs().then((data) {
        return data.map((item) => FAQ.fromJson(item as Map<String, dynamic>)).toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF3F4F8),
      appBar: AppBar(
        title: Text('자주 찾는 질문'),
        backgroundColor: Color(0xFFF3F4F8),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.help_outline, color: Colors.green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '궁금한 질문을 선택하면 답변을 확인할 수 있습니다.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<FAQ>>(
                future: _faqsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, color: Colors.red, size: 60),
                          SizedBox(height: 16),
                          Text('FAQ를 불러오는 중 오류가 발생했습니다.'),
                          SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _loadFAQs,
                            child: Text('다시 시도'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Text('등록된 FAQ가 없습니다.'),
                    );
                  }

                  final faqs = snapshot.data!;

                  return RefreshIndicator(
                    onRefresh: () async {
                      _loadFAQs();
                    },
                    child: ListView.builder(
                      itemCount: faqs.length,
                      itemBuilder: (context, index) {
                        final faq = faqs[index];
                        final isExpanded = expandedStates[faq.id] ?? false;

                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    expandedStates[faq.id] = !isExpanded;
                                  });
                                },
                                child: Container(
                                  color: Colors.transparent,
                                  padding: EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            'Q',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          faq.question,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        color: Colors.grey.shade600,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedCrossFade(
                                firstChild: Container(),
                                secondChild: Column(
                                  children: [
                                    Divider(height: 1, indent: 16, endIndent: 16),
                                    Container(
                                      padding: EdgeInsets.all(16),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: Colors.blueAccent.shade100,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                'A',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              faq.answer,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.black87,
                                                height: 1.6,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                crossFadeState: isExpanded
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                duration: const Duration(milliseconds: 300),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      // 관리자용 FAQ 추가 버튼 (선택사항)
      floatingActionButton: ApiService().isAdmin
          ? FloatingActionButton(
        onPressed: () {
          // FAQ 작성 화면으로 이동
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FAQWriteScreen(),
            ),
          ).then((value) {
            if (value == true) {
              _loadFAQs(); // 새 FAQ 추가 후 목록 새로고침
            }
          });
        },
        child: Icon(Icons.add),
      )
          : null,
    );
  }
}

class FAQWriteScreen extends StatefulWidget {
  final FAQ? faqToEdit;

  const FAQWriteScreen({super.key, this.faqToEdit});

  @override
  State<FAQWriteScreen> createState() => _FAQWriteScreenState();
}

class _FAQWriteScreenState extends State<FAQWriteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final _answerController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool get _isEditing => widget.faqToEdit != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _questionController.text = widget.faqToEdit!.question;
      _answerController.text = widget.faqToEdit!.answer;
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _saveFAQ() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isLoading = true);

    try {
      if (_isEditing) {
        await _apiService.updateFAQ(
          faqId: widget.faqToEdit!.id,
          question: _questionController.text,
          answer: _answerController.text,
        );
      } else {
        await _apiService.createFAQ(
          question: _questionController.text,
          answer: _answerController.text,
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FAQ가 성공적으로 저장되었습니다.')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'FAQ 수정' : '새 FAQ 작성'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveFAQ,
            child: _isLoading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.0,
              ),
            )
                : Text('저장'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              TextFormField(
                controller: _questionController,
                decoration: InputDecoration(
                  labelText: '질문',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                (value?.isEmpty ?? true) ? '질문을 입력해주세요.' : null,
              ),
              SizedBox(height: 16),
              Expanded(
                child: TextFormField(
                  controller: _answerController,
                  decoration: InputDecoration(
                    labelText: '답변',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  validator: (value) =>
                  (value?.isEmpty ?? true) ? '답변을 입력해주세요.' : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  _FavoritesScreenState createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final ApiService _apiService = ApiService();

  // 문법 즐겨찾기 목록과 단어장 목록을 불러오는 Future
  late Future<List<Wordbook>> _wordbooksFuture;
  late Future<List<TestQuestion>> _grammarQuestionsFuture;
  late Future<List<GrammarHistory>> _grammarHistoryFavoritesFuture;

  bool _isGrammarExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void _loadInitialData() {
    setState(() {
      _wordbooksFuture = _apiService.getWordbooks().then((data) =>
          data.map((item) => Wordbook.fromJson(item)).toList()
      );
      _grammarQuestionsFuture = _apiService.getFavoriteGrammarQuestions();
      _grammarHistoryFavoritesFuture = _apiService.getFavoriteGrammarHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('즐겨찾기'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _loadInitialData(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- 단어 즐겨찾기 섹션 ---
            _buildSectionHeader('단어장', Icons.book),
            _buildWordbookList(), // 단어장 목록을 버튼 형태로 표시
            const SizedBox(height: 24),

            // --- 문법 즐겨찾기 섹션 ---
            _buildSectionHeader('문법', Icons.menu_book),
            _buildFavoriteGrammarList(),
          ],
        ),
      ),
    );
  }

  // 단어장 목록을 버튼 리스트로 보여주는 위젯
  Widget _buildWordbookList() {
    return FutureBuilder<List<Wordbook>>(
      future: _wordbooksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('단어장 목록을 불러오는 중...'),
          ));
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline, color: Colors.grey),
              title: Text('즐겨찾기를 추가할 단어장이 없습니다.'),
            ),
          );
        }

        final wordbooks = snapshot.data!;
        return Column(
          children: wordbooks.map((wb) {
            return Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                leading: const Icon(Icons.folder_special_outlined, color: Colors.amber),
                title: Text(wb.name),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // 새로운 화면으로 이동
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FavoriteWordsByWordbookScreen(wordbook: wb),
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // 문법 즐겨찾기 목록을 보여주는 위젯 (기존 코드와 동일)
  Widget _buildFavoriteGrammarList() {
    return FutureBuilder<List<dynamic>>(
      // Future.wait를 사용해 두 개의 API 호출이 모두 끝날 때까지 기다립니다.
      future: Future.wait([
        _grammarQuestionsFuture,
        _grammarHistoryFavoritesFuture,
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('오류: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('즐겨찾기된 문법이 없습니다.'));
        }

        // API 호출 결과를 각각의 리스트에 담습니다.
        final favoriteQuestions = snapshot.data![0] as List<TestQuestion>;
        final favoriteHistories = snapshot.data![1] as List<GrammarHistory>;

        // [핵심] 두 리스트를 하나의 위젯 리스트로 변환하여 합칩니다.
        final List<Widget> allGrammarItems = [
          ...favoriteQuestions.map((question) => _buildGrammarQuestionCard(question)),
          ...favoriteHistories.map((history) => _buildGrammarHistoryCard(history)),
        ];

        if (allGrammarItems.isEmpty) {
          return const Center(child: Text('즐겨찾기된 문법이 없습니다.'));
        }

        final itemsToShow = _isGrammarExpanded ? allGrammarItems : allGrammarItems.take(3).toList();

        return Column(
          children: [
            ...itemsToShow,
            if (allGrammarItems.length > 3)
              TextButton(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isGrammarExpanded ? '접기' : '더보기'),
                    Icon(_isGrammarExpanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
                onPressed: () {
                  setState(() {
                    _isGrammarExpanded = !_isGrammarExpanded;
                  });
                },
              )
          ],
        );
      },
    );
  }

  // --- 헬퍼 위젯 (UI 구성요소) ---

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 12.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.green),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildGrammarQuestionCard(TestQuestion question) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: RichText(
          text: TextSpan(
            // RichText에 기본 스타일 적용
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black, // 👈 색상 지정 필수
              fontFamily: 'Pretendard',
            ),
            children: buildFeedbackSpans(question.text.replaceAll('____', '...')),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.star, color: Colors.amber),
          onPressed: () async {
            try {
              await _apiService.toggleGrammarQuestionFavorite(
                  questionId: question.id, isFavorite: false);
              _loadInitialData();
            } catch (e) {
              // 에러 처리
            }
          },
        ),
      ),
    );
  }

  Widget _buildGrammarHistoryCard(GrammarHistory historyItem) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black, // 👈 색상 지정 필수
              fontFamily: 'Pretendard',
            ),
            children: buildFeedbackSpans(historyItem.correctedText),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: RichText(
            text: TextSpan(
              style: TextStyle( // 👈 기본 스타일
                color: Colors.grey.shade600,
                fontSize: 13,
                fontFamily: 'Pretendard',
              ),
              children: [
                const TextSpan(text: '제출: '),
                // '제출:' 뒤에 오는 텍스트에만 buildFeedbackSpans 적용
                ...buildFeedbackSpans(historyItem.transcribedText),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.star, color: Colors.amber),
          onPressed: () async {
            try {
              await _apiService.updateGrammarFavoriteStatus(
                  historyId: historyItem.id, isFavorite: false);
              _loadInitialData();
            } catch (e) {
              // 에러 처리
            }
          },
        ),
      ),
    );
  }
}


// ▼▼▼ 2. 신규 화면 위젯 추가 ▼▼▼
// FavoritesScreen 클래스 아래에 이 새로운 클래스를 추가해주세요.

class FavoriteWordsByWordbookScreen extends StatefulWidget {
  final Wordbook wordbook;

  const FavoriteWordsByWordbookScreen({super.key, required this.wordbook});

  @override
  State<FavoriteWordsByWordbookScreen> createState() => _FavoriteWordsByWordbookScreenState();
}

class _FavoriteWordsByWordbookScreenState extends State<FavoriteWordsByWordbookScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<UserWord>> _favoriteWordsFuture;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  void _loadFavorites() {
    setState(() {
      // API를 호출하여 이 단어장의 모든 단어를 가져온 후, 즐겨찾기된 것만 필터링합니다.
      _favoriteWordsFuture = _apiService.getWordbookDetails(widget.wordbook.id).then(
              (details) => (details['words'] as List)
              .map((item) => UserWord.fromJson(item))
              .where((word) => word.isFavorite)
              .toList()
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('"${widget.wordbook.name}" 즐겨찾기'),
      ),
      body: FutureBuilder<List<UserWord>>(
        future: _favoriteWordsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('즐겨찾기된 단어가 없습니다.'));
          }

          final words = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _loadFavorites(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: words.length,
              itemBuilder: (context, index) {
                return _buildWordCard(words[index]);
              },
            ),
          );
        },
      ),
    );
  }

  // 단어 카드 UI (기존 FavoritesScreen의 것을 재사용)
  Widget _buildWordCard(UserWord wordData) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(wordData.word, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(wordData.definition),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.star, color: Colors.amber),
          onPressed: () async {
            try {
              await _apiService.updateWordFavoriteStatus(wordId: wordData.id, isFavorite: false);
              _loadFavorites(); // 즐겨찾기 해제 후 현재 화면 새로고침
            } catch (e) {
              // 에러 처리
            }
          },
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final UserProfile userProfile;
  const SettingsScreen({Key? key, required this.userProfile}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _beginnerMode = false;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _beginnerMode = AppState.beginnerMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        title: const Text('환경설정'),
        backgroundColor: const Color(0xFFF3F4F8),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // [핵심 추가] 초보자 모드 토글 버튼
            Card(
              child: SwitchListTile(
                title: const Text('초보자 모드 (해석 보기)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                subtitle: const Text('회화 학습 시 AI 답변의 한국어 해석을 함께 표시합니다.'),
                secondary: const Icon(Icons.translate_outlined),
                value: _beginnerMode,
                onChanged: (bool value) async {
                  // 1. UI를 즉시 업데이트하여 사용자 경험을 향상시킵니다.
                  setState(() {
                    _beginnerMode = value;
                  });

                  try {
                    // 2. 서버 DB에 변경된 설정값을 저장합니다.
                    await _apiService.updateBeginnerMode(isEnabled: value);
                    // 3. 앱의 전역 상태(AppState)에도 최종 반영합니다.
                    AppState.beginnerMode = value;
                    if (mounted) {
                      // ▼▼▼ [수정된 부분] ▼▼▼
                      // value가 true이면 '설정', false이면 '해제' 메시지를 선택
                      final message = value ? '초보자 모드가 설정되었습니다.' : '초보자 모드가 해제되었습니다.';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                      // ▲▲▲ [수정된 부분] ▲▲▲
                    }
                  } catch (e) {
                    // 4. 만약 서버 저장이 실패하면, UI를 원래 상태로 되돌립니다.
                    setState(() {
                      _beginnerMode = !value;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('초보자 모드 설정 저장에 실패했습니다: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                activeColor: Colors.green,
              ),
            ),
            const SizedBox(height: 24),

            // --- 기존 설정 버튼들은 그대로 유지 ---
            _buildSettingButton(
              context,
              icon: Icons.notifications_outlined,
              title: '알림 설정',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => NotificationSettingsScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildSettingButton(
              context,
              icon: Icons.language_outlined,
              title: '언어 선택',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => LanguageSelectionScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildCharacterButton(context),
            const SizedBox(height: 24),
            _buildSettingButton(
              context,
              icon: Icons.help_outline,
              title: '자주 찾는 질문',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => FAQScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildSettingButton(
              context,
              icon: Icons.feedback_outlined,
              title: '피드백 작성',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => FeedbackScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildSettingButton(
              context,
              icon: Icons.campaign_outlined,
              title: '공지사항',
              onTap: () {
                final bool isAdmin = widget.userProfile.isAdmin;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => NoticeListScreen(isAdmin: isAdmin)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 헬퍼 위젯들은 State 클래스 안으로 이동
  Widget _buildCharacterButton(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        // 1. CharacterSelectionScreen으로 이동하고, 결과가 돌아올 때까지 기다립니다.
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            // 2. isFromSettings: true를 전달하여 '설정에서 왔다'는 것을 알려줍니다.
            builder: (context) => CharacterSelectionScreen(isFromSettings: true),
          ),
        );
        // 3. 만약 캐릭터 변경이 성공적으로 완료되었다면(true 반환),
        //    설정 화면의 UI를 새로고침하여 변경된 캐릭터 이미지를 즉시 반영합니다.
        if (result == true && mounted) {
          setState(() {});
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  AppState.selectedCharacterImage,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(Icons.pets, size: 18, color: Colors.green);
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                '캐릭터 선택',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingButton(BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.grey.shade700),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// 언어 선택 화면
class LanguageSelectionScreen extends StatefulWidget {
  @override
  _LanguageSelectionScreenState createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  final ApiService _apiService = ApiService();
  String? selectedLanguage;
  bool _isLoading = false; // 로딩 상태 관리를 위한 변수 추가

  final List<Map<String, dynamic>> languages = [
    {'name': '영어', 'code': 'en', 'flag': '🇺🇸'},
    {'name': '일본어', 'code': 'ja', 'flag': '🇯🇵'},
    {'name': '중국어', 'code': 'zh', 'flag': '🇨🇳'},
    {'name': '불어', 'code': 'fr', 'flag': '🇫🇷'},
  ];

  @override
  void initState() {
    super.initState();
    // 현재 AppState에 설정된 언어를 기본 선택값으로 설정합니다.
    selectedLanguage = AppState.targetLanguage;
  }

  // [핵심 수정] 언어 설정을 저장하고 홈 화면으로 이동하는 함수
  Future<void> _saveAndNavigate() async {
    if (selectedLanguage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('학습할 언어를 선택해주세요.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 선택된 언어의 이름(예: "일본어")으로 코드(예: "ja")를 찾습니다.
      final targetLangData = languages.firstWhere(
            (lang) => lang['name'] == selectedLanguage,
        orElse: () => {'code': 'en'}, // 혹시 못찾을 경우 영어로 기본값 설정
      );
      final targetLangCode = targetLangData['code'];

      // AppState에 저장된 현재 모국어 설정도 코드로 변환합니다.
      // 모국어 설정이 없는 경우 기본값으로 'ko'를 사용합니다.
      final nativeLangName = AppState.nativeLanguage ?? '한국어';
      final nativeLangCode = AppState._languageCodeToName.entries
          .firstWhere((entry) => entry.value == nativeLangName, orElse: () => const MapEntry('ko', '한국어'))
          .key;

      // 서버에 변경된 모국어와 학습 언어 설정을 함께 저장합니다.
      await _apiService.updateUserLanguages(
        nativeLanguage: nativeLangCode,
        targetLanguage: targetLangCode,
      );

      // AppState를 최신 정보로 업데이트합니다.
      final updatedProfile = await _apiService.getUserProfile();
      AppState.updateFromProfile(updatedProfile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${selectedLanguage}으로 언어가 변경되었습니다!')),
        );
        // 모든 이전 화면을 닫고 새로운 홈 화면으로 이동합니다.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(isAdmin: _apiService.isAdmin, refresh: true)),
              (route) => false,
        );
      }
    } on ApiException catch(e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('언어 변경 실패: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        title: const Text('언어 선택'),
        backgroundColor: const Color(0xFFF3F4F8),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              '회화 학습에서 공부하고 싶은\n언어를 선택하세요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: ListView.builder(
                itemCount: languages.length,
                itemBuilder: (context, index) {
                  final language = languages[index];
                  final isSelected = selectedLanguage == language['name'];

                  return GestureDetector(
                    onTap: () => setState(() => selectedLanguage = language['name']),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.green : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Center(child: Text(language['flag'], style: const TextStyle(fontSize: 28))),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Text(
                              language['name'],
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Colors.green)
                          else
                            Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // [수정] onPressed에 새로 만든 _saveAndNavigate 함수를 연결합니다.
                onPressed: selectedLanguage != null && !_isLoading
                    ? _saveAndNavigate
                    : null,
                child: _isLoading
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                )
                    : const Text('완료'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GoalSettingScreen extends StatefulWidget {
  const GoalSettingScreen({super.key});

  @override
  State<GoalSettingScreen> createState() => _GoalSettingScreenState();
}

class _GoalSettingScreenState extends State<GoalSettingScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true; // 데이터를 불러오는 중인지 여부
  int? _existingPlanId; // 기존 계획의 ID를 저장할 변수

  double _conversationDuration = 30.0;
  double _grammarCount = 3.0;
  double _pronunciationCount = 3.0;

  @override
  void initState() {
    super.initState();
    _loadExistingPlan();
  }

  // 기존 학습 계획을 불러와 UI에 반영하는 함수
  Future<void> _loadExistingPlan() async {
    try {
      final latestPlan = await _apiService.getLatestLearningPlan();

      if (latestPlan != null && mounted) {
        setState(() {
          _existingPlanId = latestPlan['id'];
          final Map<String, dynamic> timeDistribution = latestPlan['time_distribution'];

          _conversationDuration = (timeDistribution['conversation'] ?? 30).toDouble();
          _grammarCount = (timeDistribution['grammar'] ?? 3).toDouble();
          _pronunciationCount = (timeDistribution['pronunciation'] ?? 3).toDouble();
        });
      }
    } catch (e) {
      print("기존 학습 계획 없음 (또는 로드 중 오류 발생): $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // '저장' 버튼을 눌렀을 때 호출되는 함수 (생성/수정 분기 처리)
  Future<void> _saveGoal() async {
    setState(() => _isLoading = true);

    try {
      if (_existingPlanId != null) {
        // --- 수정 로직 ---
        await _apiService.updateLearningPlan(
          planId: _existingPlanId!,
          conversationDuration: _conversationDuration.toInt(),
          grammarCount: _grammarCount.toInt(),
          pronunciationCount: _pronunciationCount.toInt(),
        );
      } else {
        // --- 생성 로직 ---
        await _apiService.createLearningPlan(
          conversationDuration: _conversationDuration.toInt(),
          grammarCount: _grammarCount.toInt(),
          pronunciationCount: _pronunciationCount.toInt(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('학습 목표가 성공적으로 저장되었습니다!')),
        );

        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => CharacterSelectionScreen()),
                (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('학습 목표 설정')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('추천 플랜에서 선택하기'),
            onPressed: () async {
              final newProfile = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(builder: (context) => const PlanTemplateScreen()),
              );

              if (newProfile != null && mounted) {
                AppState.updateFromProfile(newProfile);
                if (Navigator.canPop(context)) {
                  Navigator.pop(context, true);
                } else {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => CharacterSelectionScreen()),
                        (route) => false,
                  );
                }
              }
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Text('OR'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),

          const Center(child: Text("직접 목표 설정하기", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          const SizedBox(height: 24),

          // ▼▼▼ [수정] UI를 3개의 개별 슬라이더로 변경 ▼▼▼
          _buildSliderSection(
              '회화 학습 시간 (분)',
              _conversationDuration,
                  (val) => setState(() => _conversationDuration = val),
              min: 0, max: 120, divisions: 12
          ),
          const Divider(height: 40),
          _buildSliderSection(
              '문법 학습 횟수 (회)',
              _grammarCount,
                  (val) => setState(() => _grammarCount = val),
              min: 0, max: 20, divisions: 20
          ),
          const Divider(height: 40),
          _buildSliderSection(
              '발음 학습 횟수 (회)',
              _pronunciationCount,
                  (val) => setState(() => _pronunciationCount = val),
              min: 0, max: 20, divisions: 20
          ),
          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: _saveGoal,
            child: Text(_existingPlanId != null ? '학습 목표 수정하기' : '학습 목표 저장하기'),
          ),
        ],
      ),
    );
  }

  // UI 헬퍼 위젯 (수정 없이 그대로 사용)
  Widget _buildSliderSection(String title, double value, ValueChanged<double> onChanged, {double min = 1, double max = 10, int? divisions = 9}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title: ${value.toInt()}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Slider(value: value, min: min, max: max, divisions: divisions, label: value.toInt().toString(), onChanged: onChanged),
      ],
    );
  }
}

class Notice {
  final int id;
  final String title;
  final String content;
  final DateTime createdAt;

  Notice({required this.id, required this.title, required this.content, required this.createdAt});

  factory Notice.fromJson(Map<String, dynamic> json) {
    return Notice(
      id: json['id'],
      title: json['title'] ?? '제목 없음',
      content: json['content'] ?? '내용 없음',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class NoticeListScreen extends StatefulWidget {
  final bool isAdmin; // isAdmin 변수를 받도록 추가

  const NoticeListScreen({super.key, required this.isAdmin}); // 생성자 수정

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  late Future<List<Notice>> _noticesFuture;

  @override
  void initState() {
    super.initState();
    _fetchNotices();
  }

  void _fetchNotices() {
    setState(() {
      _noticesFuture = ApiService().getNotices().then((data) =>
          data.map((item) => Notice.fromJson(item as Map<String, dynamic>)).toList()
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    print('NoticeListScreen - isAdmin: ${widget.isAdmin}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('공지사항'),
      ),
      // isAdmin이 true일 때만 FloatingActionButton을 표시합니다.
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
        onPressed: () {
          print('공지사항 작성 버튼 클릭됨');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NoticeWriteScreen(),
            ),
          ).then((value) {
            // 공지사항 작성 후 목록 갱신
            if (value == true) {
              _fetchNotices();
            }
          });
        },
        child: const Icon(Icons.add),
      )
          : null, // false일 경우 null을 반환하여 버튼을 숨깁니다.
      body: FutureBuilder<List<dynamic>>(
        future: _noticesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('오류: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('공지사항이 없습니다.'));
          } else {
            final notices = snapshot.data!;
            return RefreshIndicator(
              onRefresh: () async {
                _fetchNotices();
              },
              child: ListView.builder(
                itemCount: notices.length,
                itemBuilder: (context, index) {
                  final notice = notices[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      title: Text(notice.title),
                      subtitle: Text(notice.createdAt.toLocal().toString().substring(0, 10)),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NoticeDetailScreen(
                              notice: notice,
                              isAdmin: widget.isAdmin, // isAdmin 값 전달
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            );
          }
        },
      ),
    );
  }
}

class NoticeDetailScreen extends StatelessWidget {
  final Notice notice;
  final bool isAdmin;

  const NoticeDetailScreen({super.key, required this.notice, required this.isAdmin});

  Future<void> _deleteNotice(BuildContext context) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('정말로 이 공지사항을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService().deleteNotice(notice.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공지사항이 삭제되었습니다.')));
          Navigator.pop(context); // 목록 화면으로 돌아가기
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('공지사항'),
        actions: [
          if (isAdmin) // 관리자일 경우에만 수정/삭제 버튼 표시
            IconButton(
              icon: const Icon(Icons.edit_note),
              onPressed: () {
                // 수정 화면으로 이동 (현재 화면을 교체하여 뒤로가기 시 목록으로 바로 이동)
                Navigator.pushReplacement(context, MaterialPageRoute(
                  builder: (context) => NoticeWriteScreen(noticeToEdit: notice),
                ));
              },
            ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteNotice(context),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notice.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '작성일: ${notice.createdAt.toLocal().toString().substring(0, 16)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const Divider(height: 32),
            Text(
              notice.content,
              style: const TextStyle(fontSize: 16, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class NoticeWriteScreen extends StatefulWidget {
  final Notice? noticeToEdit; // 수정할 공지 데이터 (새 글 작성 시에는 null)

  const NoticeWriteScreen({super.key, this.noticeToEdit});

  @override
  State<NoticeWriteScreen> createState() => _NoticeWriteScreenState();
}

class _NoticeWriteScreenState extends State<NoticeWriteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool get _isEditing => widget.noticeToEdit != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleController.text = widget.noticeToEdit!.title;
      _contentController.text = widget.noticeToEdit!.content;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveNotice() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isLoading = true);

    try {
      if (_isEditing) {
        // --- 수정 모드 ---
        await _apiService.updateNotice(
          noticeId: widget.noticeToEdit!.id,
          title: _titleController.text,
          content: _contentController.text,
        );
      } else {
        // --- 새 글 작성 모드 ---
        await _apiService.createNotice(
          title: _titleController.text,
          content: _contentController.text,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공지사항이 성공적으로 저장되었습니다.')));
        Navigator.pop(context); // 저장 후 목록 화면으로 돌아가기
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '공지사항 수정' : '새 공지사항 작성'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton(
              onPressed: _isLoading ? null : _saveNotice,
              child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0,)) : const Text('저장'),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
                validator: (value) => (value?.isEmpty ?? true) ? '제목을 입력해주세요.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(labelText: '내용', border: OutlineInputBorder(), alignLabelWithHint: true),
                maxLines: 15,
                validator: (value) => (value?.isEmpty ?? true) ? '내용을 입력해주세요.' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final ApiService _apiService = ApiService();
  // API로부터 받아온 알림 목록을 저장할 Future 변수
  late Future<List<model.Notification>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    // 한국어 시간 표기를 위해 timeago 라이브러리 설정
    timeago.setLocaleMessages('ko', timeago.KoMessages());
    // 페이지가 열릴 때 알림 목록을 불러옵니다.
    _notificationsFuture = _loadNotifications();
  }

  // API를 호출하여 알림 데이터를 불러오는 함수
  Future<List<model.Notification>> _loadNotifications() async {
    try {
      final data = await _apiService.getMyNotifications();
      return data.map((item) => model.Notification.fromJson(item)).toList();
    } catch (e) {
      print("알림 로딩 실패: $e");
      // 오류 발생 시 빈 리스트를 반환하여 화면에 오류 메시지를 표시하도록 유도
      throw Exception("알림을 불러오는 데 실패했습니다.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        // 새로고침 버튼
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _notificationsFuture = _loadNotifications();
            }),
          ),
        ],
      ),
      // FutureBuilder를 사용하여 비동기 데이터 로딩 상태를 관리
      body: FutureBuilder<List<model.Notification>>(
        future: _notificationsFuture,
        builder: (context, snapshot) {
          // 1. 로딩 중일 때
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // 2. 에러가 발생했을 때
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          // 3. 데이터가 없거나 비어있을 때
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('새로운 알림이 없습니다.', style: TextStyle(fontSize: 16, color: Colors.grey)),
            );
          }

          // 4. 데이터 로딩 성공 시
          final notifications = snapshot.data!;
          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Icon(notification.icon), // 모델에 정의된 아이콘 헬퍼 사용
                ),
                title: Text(notification.content),
                subtitle: Text(
                  timeago.format(notification.createdAt, locale: 'ko'), // '5분 전' 형식으로 표시
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ▼▼▼ [추가] 소셜 로그인 후 추가 정보 입력 화면 ▼▼▼
class AdditionalInfoScreen extends StatefulWidget {
  const AdditionalInfoScreen({super.key});

  @override
  State<AdditionalInfoScreen> createState() => _AdditionalInfoScreenState();
}

class _AdditionalInfoScreenState extends State<AdditionalInfoScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (AppState.userName != null && AppState.userName!.isNotEmpty) {
      _nameController.text = AppState.userName!;
    }
  }

  Future<void> _submit() async {
    // 이메일 형식 검증 추가
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    if (_emailController.text.isEmpty || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이메일과 이름을 모두 입력해주세요.'))
      );
      return;
    }

    if (!emailRegex.hasMatch(_emailController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('올바른 이메일 형식을 입력해주세요.'))
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _apiService.updateAdditionalInfo(
        email: _emailController.text,
        name: _nameController.text,
      );

      if (mounted) {
        // 정보 업데이트 후 프로필 다시 가져오기
        final updatedProfile = await _apiService.getUserProfile();
        AppState.updateFromProfile(updatedProfile);

        // 레벨 테스트로 이동
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LevelTestScreen()),
              (route) => false,
        );
      }
    } on ApiException catch(e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: Colors.red)
        );
      }
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('추가 정보 입력'),
          automaticallyImplyLeading: false
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            const Text(
              '서비스 이용을 위해\n이메일과 이름을 입력해주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, height: 1.5),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: '이메일 *',
                hintText: '예) user@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '이름 *',
                hintText: '예) 홍길동',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('완료'),
            ),
          ],
        ),
      ),
    );
  }
}

class LanguageSettingScreen extends StatefulWidget {
  const LanguageSettingScreen({super.key});

  @override
  State<LanguageSettingScreen> createState() => _LanguageSettingScreenState();
}

class _LanguageSettingScreenState extends State<LanguageSettingScreen> {
  String? _selectedNativeLanguage;
  String? _selectedTargetLanguage;
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  final List<Map<String, String>> _nativeLanguages = [
    {'name': '한국어', 'code': 'ko', 'flag': '🇰🇷'},
    {'name': '영어', 'code': 'en', 'flag': '🇺🇸'},
    {'name': '일본어', 'code': 'ja', 'flag': '🇯🇵'},
    {'name': '중국어', 'code': 'zh', 'flag': '🇨🇳'},
    {'name': '프랑스어', 'code': 'fr', 'flag': '🇫🇷'},
    {'name': '스페인어', 'code': 'es', 'flag': '🇪🇸'},
    {'name': '독일어', 'code': 'de', 'flag': '🇩🇪'},
  ];

  final List<Map<String, String>> _targetLanguages = [
    {'name': '영어', 'code': 'en', 'flag': '🇺🇸'},
    {'name': '일본어', 'code': 'ja', 'flag': '🇯🇵'},
    {'name': '중국어', 'code': 'zh', 'flag': '🇨🇳'},
    {'name': '프랑스어', 'code': 'fr', 'flag': '🇫🇷'},
  ];

  Future<void> _saveLanguages() async {
    if (_selectedNativeLanguage == null || _selectedTargetLanguage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모국어와 학습 언어를 모두 선택해주세요.')),
      );
      return;
    }

    if (_selectedNativeLanguage == _selectedTargetLanguage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모국어와 학습 언어는 달라야 합니다.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. 서버에 언어 설정 저장
      await _apiService.updateUserLanguages(
        nativeLanguage: _selectedNativeLanguage!,
        targetLanguage: _selectedTargetLanguage!,
      );

      // 2. AppState에 즉시 반영
      AppState.nativeLanguage = _nativeLanguages.firstWhere((lang) => lang['code'] == _selectedNativeLanguage)['name'];
      AppState.targetLanguage = _targetLanguages.firstWhere((lang) => lang['code'] == _selectedTargetLanguage)['name'];

      if (mounted) {
        // 3. 홈 화면으로 이동
        final userProfile = await _apiService.getUserProfile();
        final bool isAdmin = userProfile['is_admin'] ?? false;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(isAdmin: isAdmin)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('언어 설정'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              '학습을 시작하기 전에\n언어를 설정해주세요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),

            // 모국어 선택 드롭다운 (전체 언어 목록 사용)
            _buildLanguageSection(
              title: '모국어 (Native Language)',
              languages: _nativeLanguages, // 👈 여기는 전체 언어 목록 사용
              selectedLanguage: _selectedNativeLanguage,
              onChanged: (code) => setState(() => _selectedNativeLanguage = code),
            ),

            const SizedBox(height: 32),

            // 학습 언어 선택 드롭다운 (4개 언어 목록 사용)
            _buildLanguageSection(
              title: '학습 언어 (Target Language)',
              languages: _targetLanguages, // 👈 여기는 4개 언어 목록 사용
              selectedLanguage: _selectedTargetLanguage,
              onChanged: (code) => setState(() => _selectedTargetLanguage = code),
            ),

            const Spacer(),

            ElevatedButton(
              onPressed: _isLoading ? null : _saveLanguages,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('다음'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSection({
    required String title,
    required List<Map<String, String>> languages,
    required String? selectedLanguage,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedLanguage,
              isExpanded: true,
              hint: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('언어를 선택하세요'),
              ),
              items: languages.map((lang) { // 👈 파라미터로 받은 languages 사용
                return DropdownMenuItem<String>(
                  value: lang['code'],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(lang['flag']!, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Text(lang['name']!, style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class CharacterSelectionScreen extends StatefulWidget {
  // 이 화면이 설정 메뉴를 통해 들어왔는지 확인하는 변수
  final bool isFromSettings;

  const CharacterSelectionScreen({super.key, this.isFromSettings = false});

  @override
  State<CharacterSelectionScreen> createState() => _CharacterSelectionScreenState();
}

class _CharacterSelectionScreenState extends State<CharacterSelectionScreen> {
  final ApiService _apiService = ApiService();
  String? selectedCharacter;
  bool _isLoading = false;

  final List<Map<String, dynamic>> characters = [
    {'name': '여우', 'image': 'assets/fox.png'},
    {'name': '고양이', 'image': 'assets/cat.png'},
    {'name': '부엉이', 'image': 'assets/owl.png'},
    {'name': '곰', 'image': 'assets/bear.png'},
  ];

  @override
  void initState() {
    super.initState();
    selectedCharacter = AppState.selectedCharacterName ?? '여우';
  }

  // [핵심] 캐릭터를 저장하고 상황에 맞게 화면을 이동하는 통합 함수
  Future<void> _saveAndNavigate() async {
    if (selectedCharacter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('함께 공부할 캐릭터를 선택해주세요!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final selectedData = characters.firstWhere((c) => c['name'] == selectedCharacter);

      // 1. 서버에 선택한 캐릭터 정보를 저장합니다.
      final updatedProfile = await _apiService.updateUserCharacter(
        characterName: selectedData['name'],
        characterImage: selectedData['image'],
      );

      // 2. 앱의 로컬 상태(AppState)를 서버로부터 받은 최신 정보로 갱신합니다.
      AppState.updateFromProfile(updatedProfile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('캐릭터가 ${selectedCharacter}(으)로 변경되었습니다!')),
        );

        // 3. [분기 로직] 어디서 왔는지에 따라 다르게 이동합니다.
        if (widget.isFromSettings) {
          // 설정에서 왔다면 -> 모든 이전 화면을 닫고 새로운 홈 화면으로 이동합니다.
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen(isAdmin: _apiService.isAdmin)),
                (route) => false, // 모든 이전 경로를 제거합니다.
          );
        } else {
          // 초기 설정 과정이라면 -> 다음 단계인 언어 설정 화면으로 이동합니다.
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LanguageSettingScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('캐릭터 선택'),
        // 초기 설정 과정에서는 뒤로가기 버튼을 숨깁니다.
        automaticallyImplyLeading: widget.isFromSettings,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text(
                '공부를 함께 하고싶은 \n캐릭터를 선택하세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              // 설정에서 들어왔을 때만 '변경 가능' 텍스트 표시
              if (widget.isFromSettings)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Text(
                      '(추후에 변경 가능합니다)',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600)
                  ),
                ),
              const SizedBox(height: 60),
              Expanded(
                child: ListView.builder(
                  itemCount: characters.length,
                  itemBuilder: (context, index) {
                    final character = characters[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: RadioListTile<String>(
                        contentPadding: const EdgeInsets.all(12),
                        title: Row(
                          children: [
                            Image.asset(
                                character['image'],
                                width: 50,
                                height: 50,
                                errorBuilder: (c, e, s) => const Icon(Icons.pets, size: 40)
                            ),
                            const SizedBox(width: 20),
                            Text(
                                character['name'],
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)
                            ),
                          ],
                        ),
                        value: character['name'],
                        groupValue: selectedCharacter,
                        onChanged: (value) => setState(() => selectedCharacter = value),
                        activeColor: Colors.green,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _isLoading ? null : _saveAndNavigate, // 통합된 함수 호출
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(widget.isFromSettings ? '변경 완료' : '선택 완료'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudyGroupListScreen extends StatefulWidget {
  const StudyGroupListScreen({super.key});

  @override
  State<StudyGroupListScreen> createState() => _StudyGroupListScreenState();
}

class _StudyGroupListScreenState extends State<StudyGroupListScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<StudyGroup>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  void _loadGroups() {
    setState(() {
      _groupsFuture = _apiService.getStudyGroups();
    });
  }

  // 외부에서 이 위젯의 상태를 새로고침하기 위한 함수
  void refreshGroups() {
    _loadGroups();
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold와 AppBar가 제거되고 FutureBuilder가 최상위 위젯이 됩니다.
    return FutureBuilder<List<StudyGroup>>(
      future: _groupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text('오류: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadGroups,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.group_outlined, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text(
                  '아직 생성된 학습 그룹이 없습니다.\n\'그룹 만들기\' 버튼으로 시작해보세요!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final groups = snapshot.data!;

        return RefreshIndicator(
          onRefresh: () async => _loadGroups(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              return _buildGroupCard(groups[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildGroupCard(StudyGroup group) {
    final isFull = group.memberCount >= group.maxMembers;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudyGroupDetailScreen(group: group),
            ),
          ).then((value) {
            if (value == true) _loadGroups();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (group.isMember)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '참여중',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              if (group.description != null && group.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  group.description!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${group.memberCount} / ${group.maxMembers}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isFull ? Colors.red : Colors.grey.shade700,
                      fontWeight: isFull ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${group.createdAt.month}/${group.createdAt.day}',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const Spacer(),
                  if (!group.isMember && !isFull)
                    TextButton(
                      onPressed: () => _joinGroup(group.id),
                      // << [수정] 그룹 속성에 따라 버튼 텍스트 변경 >>
                      child: Text(group.requiresApproval ? '참여 요청' : '바로 참여'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _joinGroup(int groupId) async {
    try {
      // ApiService에서 성공 메시지를 문자열로 반환
      final message = await _apiService.joinStudyGroup(groupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        // '바로 참여'의 경우 목록을 즉시 새로고침하여 '참여중'으로 표시
        _loadGroups();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class StudyGroupCreateScreen extends StatefulWidget {
  const StudyGroupCreateScreen({super.key});

  @override
  State<StudyGroupCreateScreen> createState() => _StudyGroupCreateScreenState();
}

class _StudyGroupCreateScreenState extends State<StudyGroupCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxMembersController = TextEditingController(text: '10');
  int _maxMembers = 10;
  bool _requiresApproval = false;
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _maxMembersController.addListener(() {
      final value = int.tryParse(_maxMembersController.text);
      if (value != null && value != _maxMembers) {
        setState(() {
          _maxMembers = value.clamp(2, 50);
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _maxMembersController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _apiService.createStudyGroup(
        name: _nameController.text,
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        maxMembers: _maxMembers,
        requiresApproval: _requiresApproval,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('학습 그룹이 생성되었습니다!')),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('새 학습 그룹 만들기'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '그룹 이름 *',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '그룹 이름을 입력해주세요.';
                }
                if (value.trim().length < 2) {
                  return '그룹 이름은 최소 2자 이상이어야 합니다.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '그룹 소개 (선택)',
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _maxMembersController,
              decoration: const InputDecoration(
                labelText: '최대 인원 (2~50명)',
                prefixIcon: Icon(Icons.groups),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final number = int.tryParse(value ?? '');
                if (number == null) return '숫자를 입력해주세요.';
                if (number < 2 || number > 50) return '2에서 50 사이의 숫자를 입력해주세요.';
                return null;
              },
            ),
            Slider(
              value: _maxMembers.toDouble(),
              min: 2,
              max: 50,
              divisions: 48,
              label: '$_maxMembers명',
              onChanged: (value) {
                setState(() {
                  _maxMembers = value.toInt();
                  _maxMembersController.text = _maxMembers.toString();
                });
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('가입 승인제'),
              subtitle: const Text('리더의 승인이 있어야 멤버가 될 수 있습니다.'),
              value: _requiresApproval,
              onChanged: (bool value) {
                setState(() {
                  _requiresApproval = value;
                });
              },
              secondary: Icon(_requiresApproval ? Icons.lock : Icons.lock_open),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _createGroup,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('그룹 만들기'),
            ),
          ],
        ),
      ),
    );
  }
}

class StudyGroupDetailScreen extends StatefulWidget {
  final StudyGroup group;

  const StudyGroupDetailScreen({super.key, required this.group});

  @override
  State<StudyGroupDetailScreen> createState() => _StudyGroupDetailScreenState();
}

// << [수정] State 클래스에 SingleTickerProviderStateMixin 추가 >>
class _StudyGroupDetailScreenState extends State<StudyGroupDetailScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late StudyGroup _currentGroup;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.group;
    _tabController = TabController(length: 3, vsync: this);
    // 1. 탭 변경을 감지하기 위해 리스너를 추가합니다.
    _tabController.addListener(() {
      // 탭이 바뀔 때마다 화면을 다시 그리도록 setState 호출
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // 2. 위젯이 제거될 때 리스너도 함께 제거하여 메모리 누수를 방지합니다.
    _tabController.removeListener(() {});
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentGroup.name),
        actions: [
          // ... (기존 actions 코드는 변경 없음)
          if (_currentGroup.isOwner)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteGroup();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('그룹 삭제', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
        bottom: _currentGroup.isMember
            ? TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: "참여자"),
            Tab(icon: Icon(Icons.emoji_events_outlined), text: "챌린지"),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: "채팅"),
          ],
        )
            : null,
      ),
      body: Column(
        children: [
          if (_currentGroup.isMember && _tabController.index == 0) ...[
            _buildGroupInfo(),
            const Divider(height: 1, thickness: 1),
          ],
          Expanded(
            child: _currentGroup.isMember
                ? TabBarView(
              controller: _tabController,
              children: [
                StudyGroupMembersTab(groupId: _currentGroup.id),
                // ▼▼▼ [핵심 수정] isOwner 파라미터 전달 ▼▼▼
                StudyGroupChallengesTab(
                  groupId: _currentGroup.id,
                  isMember: _currentGroup.isMember,
                  isOwner: _currentGroup.isOwner, // 그룹장 여부 전달
                ),
                StudyGroupChatTab(groupId: _currentGroup.id),
              ],
            )
                : _buildNonMemberContent(),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomAction(),
    );
  }


  // [신규] 멤버가 아닐 때 보여줄 UI를 만드는 함수
  Widget _buildNonMemberContent() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            const Text(
              '그룹 멤버 전용 공간입니다',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '그룹에 참여하여 멤버, 챌린지, 커뮤니티 기능을 이용해보세요!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // [핵심 수정] _joinGroup 함수
  Future<void> _joinGroup() async {
    // 로딩 상태를 표시하기 위한 간단한 오버레이 (선택사항)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final message = await _apiService.joinStudyGroup(_currentGroup.id);

      Navigator.pop(context); // 로딩 오버레이 닫기

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );

        // [수정] "바로 참여" 성공 시, 화면을 나가는 대신 상태를 갱신하여 UI를 다시 그립니다.
        if (message.contains("그룹에 참여했습니다")) {
          setState(() {
            _currentGroup = StudyGroup(
              id: _currentGroup.id,
              name: _currentGroup.name,
              description: _currentGroup.description,
              createdBy: _currentGroup.createdBy,
              creatorName: _currentGroup.creatorName,
              maxMembers: _currentGroup.maxMembers,
              memberCount: _currentGroup.memberCount + 1, // 멤버 수 1 증가
              isMember: true, // 참여 상태를 true로 변경
              isOwner: _currentGroup.isOwner, // 오너 여부는 그대로 유지
              requiresApproval: _currentGroup.requiresApproval,
              createdAt: _currentGroup.createdAt,
            );
          });
        }
      }
    } on ApiException catch (e) {
      Navigator.pop(context); // 로딩 오버레이 닫기
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildGroupInfo() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _currentGroup.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_currentGroup.isOwner)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 4),
                      Text(
                        'OWNER',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_currentGroup.description != null &&
              _currentGroup.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _currentGroup.description!,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _buildInfoChip(
                Icons.group,
                '${_currentGroup.memberCount} / ${_currentGroup.maxMembers}',
              ),
              const SizedBox(width: 12),
              _buildInfoChip(
                Icons.calendar_today,
                '생성일: ${_currentGroup.createdAt.month}/${_currentGroup.createdAt.day}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget? _buildBottomAction() {
    if (!_currentGroup.isMember) {
      final isFull = _currentGroup.memberCount >= _currentGroup.maxMembers;
      if (isFull) return null;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _joinGroup,
            child: const Text('이 그룹에 참여하기'),
          ),
        ),
      );
    }
    if (_currentGroup.isOwner) {
      return null;
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: OutlinedButton(
          onPressed: _leaveGroup,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
          ),
          child: const Text('그룹 나가기'),
        ),
      ),
    );
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 나가기'),
        content: const Text('정말로 이 그룹에서 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _apiService.leaveStudyGroup(_currentGroup.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('그룹에서 나갔습니다.')),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 삭제'),
        content: const Text('정말로 이 그룹을 삭제하시겠습니까?\n삭제된 그룹은 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _apiService.deleteStudyGroup(_currentGroup.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('그룹이 삭제되었습니다.')),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class StudyGroupMembersTab extends StatefulWidget {
  final int groupId;
  const StudyGroupMembersTab({super.key, required this.groupId});

  @override
  _StudyGroupMembersTabState createState() => _StudyGroupMembersTabState();
}

class _StudyGroupMembersTabState extends State<StudyGroupMembersTab> {
  final ApiService _apiService = ApiService();
  late Future<List<GroupMember>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _membersFuture = _apiService.getGroupMembers(widget.groupId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GroupMember>>(
      future: _membersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('참여중인 멤버가 없습니다.'));
        }
        final members = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(member.userName.isNotEmpty ? member.userName[0] : '?')),
                title: Text(member.userName),
                trailing: member.role == 'owner'
                    ? const Chip(label: Text('OWNER'), backgroundColor: Colors.amber)
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

// 챌린지 탭 위젯 (기존 placeholder를 아래 코드로 교체)
class StudyGroupChallengesTab extends StatefulWidget {
  final int groupId;
  final bool isMember;
  final bool isOwner; // 그룹장 여부를 전달받도록 추가

  const StudyGroupChallengesTab({
    super.key,
    required this.groupId,
    required this.isMember,
    required this.isOwner,
  });

  @override
  State<StudyGroupChallengesTab> createState() => _StudyGroupChallengesTabState();
}

class _StudyGroupChallengesTabState extends State<StudyGroupChallengesTab> {
  final ApiService _apiService = ApiService();
  late Future<List<GroupChallenge>> _challengesFuture;

  @override
  void initState() {
    super.initState();
    _loadChallenges();
  }

  void _loadChallenges() {
    setState(() {
      _challengesFuture = _apiService.getGroupChallenges(widget.groupId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<GroupChallenge>>(
        future: _challengesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('챌린지 목록을 불러오는 데 실패했습니다.\n${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('진행 중인 챌린지가 없습니다.'));
          }

          final challenges = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _loadChallenges(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: challenges.length,
              itemBuilder: (context, index) {
                // ▼▼▼ [수정] 챌린지 카드를 버튼처럼 동작하도록 InkWell로 감싸기 ▼▼▼
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () async {
                      // 챌린지 상세 페이지로 이동
                      final result = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChallengeDetailScreen(
                            challenge: challenges[index],
                            isOwner: widget.isOwner,
                          ),
                        ),
                      );
                      // 상세 페이지에서 변경사항이 있었다면 목록 새로고침
                      if (result == true) {
                        _loadChallenges();
                      }
                    },
                    child: _buildChallengeCardContent(challenges[index]),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: widget.isMember
          ? FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (context) => ChallengeCreateScreen(groupId: widget.groupId)),
          );
          if (result == true) {
            _loadChallenges();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('챌린지 만들기'),
      )
          : null,
    );
  }

  // ▼▼▼ [수정] 기존 _buildChallengeCard를 내용물(Content)만 그리도록 변경 ▼▼▼
  Widget _buildChallengeCardContent(GroupChallenge challenge) {
    final daysLeft = (challenge.endDate.difference(DateTime.now()).inHours / 24).ceil();
    final bool isMyChallenge = challenge.creatorId == AppState.userId;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challenge.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('by ${challenge.creatorName}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (daysLeft > 0)
                Chip(
                  label: Text('D-$daysLeft', style: const TextStyle(color: Colors.white)),
                  backgroundColor: daysLeft > 3 ? Colors.green : Colors.orange,
                )
              else
                const Chip(label: Text('종료'), backgroundColor: Colors.grey),
            ],
          ),
          if(challenge.description != null && challenge.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(challenge.description!, style: TextStyle(color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 16),
          // --- 진행률 바 대신 '완료한 멤버' 정보 표시 ---
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: Colors.amber.shade700, size: 18),
              const SizedBox(width: 8),
              Text('${challenge.participants.length}명 완료'),
              const Spacer(),
              // 내가 이미 완료했다면 '완료됨' 표시
              if (challenge.userHasCompleted)
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.blue, size: 16),
                    SizedBox(width: 4),
                    Text('나의 성공', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                )
            ],
          ),
        ],
      ),
    );
  }
}


// ▼▼▼ [신규] 챌린지 상세 페이지 위젯 ▼▼▼
class ChallengeDetailScreen extends StatefulWidget {
  final GroupChallenge challenge;
  final bool isOwner;

  const ChallengeDetailScreen({
    super.key,
    required this.challenge,
    required this.isOwner,
  });

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 그룹장이면 탭 3개, 아니면 2개
    _tabController = TabController(length: widget.isOwner ? 3 : 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Tab> tabs = [
      const Tab(text: '인증하기'),
      const Tab(text: '완료한 멤버'),
    ];
    if (widget.isOwner) {
      tabs.add(const Tab(text: '인증 관리'));
    }

    List<Widget> tabViews = [
      ChallengeSubmissionTab(challengeId: widget.challenge.id),
      ChallengeParticipantsTab(challengeId: widget.challenge.id),
    ];
    if (widget.isOwner) {
      tabViews.add(ChallengeApprovalTab(challengeId: widget.challenge.id));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.challenge.title),
        bottom: TabBar(
          controller: _tabController,
          tabs: tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: tabViews,
      ),
    );
  }
}

// ▼▼▼ [신규] 인증하기 탭 ▼▼▼
class ChallengeSubmissionTab extends StatefulWidget {
  final int challengeId;
  const ChallengeSubmissionTab({super.key, required this.challengeId});

  @override
  State<ChallengeSubmissionTab> createState() => _ChallengeSubmissionTabState();
}

class _ChallengeSubmissionTabState extends State<ChallengeSubmissionTab> {
  final _apiService = ApiService();
  Future<ChallengeSubmission?>? _submissionFuture;

  @override
  void initState() {
    super.initState();
    _loadMySubmission();
  }

  void _loadMySubmission() {
    setState(() {
      _submissionFuture = _apiService.getMyChallengeSubmission(widget.challengeId);
    });
  }

  Future<void> _deleteSubmission(int submissionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('인증 삭제'),
        content: const Text('정말로 이 인증 내역을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiService.deleteChallengeSubmission(submissionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('인증 내역이 삭제되었습니다.')));
        _loadMySubmission(); // 삭제 성공 후 목록 새로고침
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChallengeSubmission?>(
      future: _submissionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('오류: ${snapshot.error}'));
        }

        final submission = snapshot.data;

        // 내 인증 내역이 없으면 '인증샷 올리기' 버튼 표시
        if (submission == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => ChallengeSubmissionScreen(challengeId: widget.challengeId)),
                  );
                  // 제출 화면에서 true를 반환하면 (제출 성공 시), 내역을 다시 불러옴
                  if (result == true) {
                    _loadMySubmission();
                  }
                },
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('인증샷 올리기'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          );
        }

        // 내 인증 내역이 있으면 상세 정보 표시
        return _buildSubmissionDetailsCard(submission);
      },
    );
  }

  // 인증 내역을 보여주는 카드 위젯
  Widget _buildSubmissionDetailsCard(ChallengeSubmission submission) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        if (submission.proofImageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              submission.proofImageUrl!,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                return progress == null ? child : const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (context, error, stack) {
                return const Center(child: Text('이미지를 불러올 수 없습니다.'));
              },
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('제출 내용', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    _buildStatusChip(submission.status),
                    PopupMenuButton<String>(
                      // ▼▼▼ [핵심 수정] 이 부분을 수정합니다. ▼▼▼
                      onSelected: (value) async { // 1. async 키워드 추가
                        if (value == 'edit') {
                          // 2. await로 화면 이동을 기다리고, 결과를 받습니다.
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChallengeSubmissionScreen(
                                challengeId: widget.challengeId,
                                submissionToEdit: submission,
                              ),
                            ),
                          );
                          // 3. 만약 결과가 true이면 (수정 성공 시), 화면을 새로고침합니다.
                          if (result == true) {
                            _loadMySubmission();
                          }
                        } else if (value == 'delete') {
                          _deleteSubmission(submission.id);
                        }
                      },
                      // ▲▲▲ [수정 완료] ▲▲▲
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('수정하기')),
                        const PopupMenuItem(value: 'delete', child: Text('삭제하기', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text(
                  submission.proofContent ?? '작성된 내용이 없습니다.',
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }

  // 인증 상태를 보여주는 칩 위젯
  Widget _buildStatusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'approved':
        color = Colors.green;
        label = '승인 완료';
        break;
      case 'rejected':
        color = Colors.red;
        label = '반려됨';
        break;
      default:
        color = Colors.orange;
        label = '승인 대기중';
    }
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
    );
  }
}

// ▼▼▼ [신규] 완료한 멤버 탭 ▼▼▼
class ChallengeParticipantsTab extends StatefulWidget {
  final int challengeId;
  const ChallengeParticipantsTab({super.key, required this.challengeId});

  @override
  State<ChallengeParticipantsTab> createState() => _ChallengeParticipantsTabState();
}

class _ChallengeParticipantsTabState extends State<ChallengeParticipantsTab> {
  final _apiService = ApiService();
  late Future<List<ChallengeParticipant>> _participantsFuture;

  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  void _loadParticipants() {
    setState(() {
      _participantsFuture = _apiService.getChallengeParticipants(widget.challengeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChallengeParticipant>>(
      future: _participantsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('오류: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('아직 챌린지를 완료한 멤버가 없습니다.'));
        }

        final participants = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _loadParticipants(),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: participants.length,
            itemBuilder: (context, index) {
              final participant = participants[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(participant.userName.isNotEmpty ? participant.userName[0] : '?'),
                  ),
                  title: Text(participant.userName),
                  subtitle: Text('완료: ${participant.completedAt.toLocal().toString().substring(0, 10)}'),
                  trailing: Text(
                    '${index + 1}등',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: index < 3 ? Colors.amber.shade800 : Colors.grey,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ▼▼▼ [신규] 인증 관리 탭 (그룹장 전용) ▼▼▼
class ChallengeApprovalTab extends StatefulWidget {
  final int challengeId;
  const ChallengeApprovalTab({super.key, required this.challengeId});

  @override
  State<ChallengeApprovalTab> createState() => _ChallengeApprovalTabState();
}

class _ChallengeApprovalTabState extends State<ChallengeApprovalTab> {
  final ApiService _apiService = ApiService();
  late Future<List<ChallengeSubmission>> _submissionsFuture;
  final Set<int> _processingIds = {};

  // 펼쳐진 아이템의 ID를 저장하기 위한 Set 추가
  final Set<int> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  void _loadSubmissions() {
    setState(() {
      _submissionsFuture = _apiService.getChallengeSubmissions(widget.challengeId);
    });
  }

  Future<void> _processSubmission(int submissionId, String status) async {
    if (_processingIds.contains(submissionId)) return;
    setState(() => _processingIds.add(submissionId));
    try {
      final result = await _apiService.processChallengeSubmission(submissionId: submissionId, status: status);
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
        _loadSubmissions();
      }
    } on ApiException catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: ${e.message}'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _processingIds.remove(submissionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 이제 이 위젯이 직접 목록을 보여줍니다.
    return FutureBuilder<List<ChallengeSubmission>>(
      future: _submissionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('오류: ${snapshot.error}'));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('관리할 인증 내역이 없습니다.'));

        final submissions = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _loadSubmissions(),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: submissions.length,
            itemBuilder: (context, index) => _buildSubmissionCard(submissions[index]),
          ),
        );
      },
    );
  }

  // 각 인증 내역을 보여주는 카드 위젯
  Widget _buildSubmissionCard(ChallengeSubmission submission) {
    final isProcessing = _processingIds.contains(submission.id);
    final isExpanded = _expandedIds.contains(submission.id); // 현재 아이템이 펼쳐졌는지 확인

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      clipBehavior: Clip.antiAlias, // 자식 위젯이 카드를 벗어나지 않도록
      child: InkWell( // 탭 이벤트를 위해 InkWell 사용
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedIds.remove(submission.id);
            } else {
              _expandedIds.add(submission.id);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 항상 보이는 부분 ---
              Row(
                children: [
                  CircleAvatar(child: Text(submission.userName.isNotEmpty ? submission.userName[0] : '?')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(submission.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(timeago.format(submission.submittedAt, locale: 'ko'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
                ],
              ),

              // --- 펼쳤을 때만 보이는 부분 ---
              AnimatedCrossFade(
                firstChild: Container(), // 접혔을 때
                secondChild: Column( // 펼쳐졌을 때
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 24),
                    if (submission.proofImageUrl != null)
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(submission.proofImageUrl!)),
                    if (submission.proofContent != null && submission.proofContent!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(submission.proofContent!),
                    ],
                    const SizedBox(height: 16),
                    if (submission.status == 'pending')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isProcessing) const CircularProgressIndicator(),
                          if (!isProcessing) ...[
                            TextButton(onPressed: () => _processSubmission(submission.id, 'rejected'), child: const Text('거절', style: TextStyle(color: Colors.red))),
                            const SizedBox(width: 8),
                            ElevatedButton(onPressed: () => _processSubmission(submission.id, 'approved'), child: const Text('승인')),
                          ]
                        ],
                      )
                    else
                      Align(alignment: Alignment.centerRight, child: _buildStatusChip(submission.status)),
                  ],
                ),
                crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 인증 상태 칩 위젯 (기존과 동일)
  Widget _buildStatusChip(String status) {
    Color color; String label;
    switch (status) {
      case 'approved': color = Colors.green; label = '승인 완료'; break;
      case 'rejected': color = Colors.red; label = '반려됨'; break;
      default: color = Colors.orange; label = '승인 대기중';
    }
    return Chip(label: Text(label, style: const TextStyle(color: Colors.white)), backgroundColor: color);
  }
}

// << [추가] 그룹 채팅 탭 위젯 >>
class StudyGroupChatTab extends StatefulWidget {
  final int groupId;
  const StudyGroupChatTab({super.key, required this.groupId});

  @override
  _StudyGroupChatTabState createState() => _StudyGroupChatTabState();
}

class _StudyGroupChatTabState extends State<StudyGroupChatTab> {
  final ApiService _apiService = ApiService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<StudyGroupMessage> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _apiService.getGroupMessages(widget.groupId);
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    final content = _messageController.text;
    _messageController.clear();

    try {
      final newMessage = await _apiService.postGroupMessage(widget.groupId, content);
      setState(() {
        _messages.add(newMessage);
      });
      _scrollToBottom();
    } catch (e) {
      // Handle error
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isMe = msg.userId == AppState.userId;
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.green[100] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(isMe ? '나' : msg.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(msg.content),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: '메시지 입력...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}

class PronunciationHistoryScreen extends StatefulWidget {
  const PronunciationHistoryScreen({super.key});

  @override
  State<PronunciationHistoryScreen> createState() => _PronunciationHistoryScreenState();
}

class _PronunciationHistoryScreenState extends State<PronunciationHistoryScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<PronunciationHistory>> _historyFuture;
  late Future<PronunciationStatistics> _statsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _historyFuture = _apiService.getPronunciationHistory();
      _statsFuture = _apiService.getPronunciationStatistics();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('발음 분석 이력'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatisticsCard(),
          const Divider(height: 1),
          Expanded(child: _buildHistoryList()),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return FutureBuilder<PronunciationStatistics>(
      future: _statsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 150,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final stats = snapshot.data!;

        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bar_chart, color: Colors.green),
                    const SizedBox(width: 8),
                    const Text(
                      '전체 통계',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      '총 ${stats.totalCount}회',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('평균', stats.averageOverall, Colors.blue),
                    _buildStatItem('정확도', stats.averagePhoneme, Colors.teal),
                    _buildStatItem('음높이', stats.averagePitch, Colors.orange),
                    _buildStatItem('리듬', stats.averageRhythm, Colors.green),
                    _buildStatItem('강세', stats.averageStress, Colors.red),
                  ],
                ),
                if (stats.recentImprovement != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: stats.recentImprovement! > 0
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          stats.recentImprovement! > 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 16,
                          color: stats.recentImprovement! > 0
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '최근 ${stats.recentImprovement!.abs().toStringAsFixed(1)}점 ${stats.recentImprovement! > 0 ? "상승" : "하락"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: stats.recentImprovement! > 0
                                ? Colors.green.shade800
                                : Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, double score, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          score.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    return FutureBuilder<List<PronunciationHistory>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text('오류: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadData,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic_none, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text(
                  '아직 발음 학습 기록이 없습니다.\n학습 화면에서 발음 학습을 시작해보세요!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final history = snapshot.data!;

        return RefreshIndicator(
          onRefresh: () async => _loadData(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            itemBuilder: (context, index) {
              return _buildHistoryCard(history[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildHistoryCard(PronunciationHistory item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PronunciationHistoryDetailScreen(history: item),
            ),
          ).then((value) {
            if (value == true) _loadData();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.targetText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildScoreBadge(item.overallScore),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMiniScore('정확도', item.phonemeScore, Colors.teal),
                  _buildMiniScore('음높이', item.pitchScore, Colors.orange),
                  _buildMiniScore('리듬', item.rhythmScore, Colors.green),
                  _buildMiniScore('강세', item.stressScore, Colors.red),
                  if (item.fluencyScore != null)
                    _buildMiniScore('유창성', item.fluencyScore!, Colors.purple),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${item.createdAt.year}/${item.createdAt.month}/${item.createdAt.day} ${item.createdAt.hour}:${item.createdAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreBadge(double score) {
    Color color;
    if (score >= 80) {
      color = Colors.green;
    } else if (score >= 60) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Text(
        score.toStringAsFixed(0),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMiniScore(String label, double score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            score.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class PronunciationHistoryDetailScreen extends StatefulWidget {
  final PronunciationHistory history;

  const PronunciationHistoryDetailScreen({super.key, required this.history});

  @override
  State<PronunciationHistoryDetailScreen> createState() => _PronunciationHistoryDetailScreenState();
}

class _PronunciationHistoryDetailScreenState extends State<PronunciationHistoryDetailScreen> {
  final ApiService _apiService = ApiService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('발음 분석 상세'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _deleteHistory();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('삭제', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTargetTextCard(),
            const SizedBox(height: 16),
            _buildScoresCard(),
            const SizedBox(height: 16),
            if (widget.history.misstressedWords != null &&
                widget.history.misstressedWords!.isNotEmpty)
              _buildMisstressedWordsCard(),
            if (widget.history.misstressedWords != null &&
                widget.history.misstressedWords!.isNotEmpty)
              const SizedBox(height: 16),
            _buildFeedbackCard(),
            const SizedBox(height: 16),
            _buildSuggestionsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetTextCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.text_fields, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '학습한 문장',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.history.targetText,
              style: const TextStyle(fontSize: 18, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.history.createdAt.year}년 ${widget.history.createdAt.month}월 ${widget.history.createdAt.day}일',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoresCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  '점수 분석',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildScoreIndicator('종합 점수', widget.history.overallScore, Colors.blue),
            const SizedBox(height: 16),
            _buildScoreIndicator('정확도', widget.history.phonemeScore, Colors.teal),
            const SizedBox(height: 16),
            _buildScoreIndicator('음높이', widget.history.pitchScore, Colors.orange),
            const SizedBox(height: 16),
            _buildScoreIndicator('리듬', widget.history.rhythmScore, Colors.green),
            const SizedBox(height: 16),
            _buildScoreIndicator('강세', widget.history.stressScore, Colors.red),
            if (widget.history.fluencyScore != null) ...[
              const SizedBox(height: 16),
              _buildScoreIndicator('유창성', widget.history.fluencyScore!, Colors.purple),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreIndicator(String title, double score, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            Text(
              score.toStringAsFixed(1),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: score / 100,
          minHeight: 10,
          backgroundColor: color.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          borderRadius: BorderRadius.circular(5),
        ),
      ],
    );
  }

  Widget _buildMisstressedWordsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  '강세 오류 단어',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.history.misstressedWords!.map((word) {
                return Chip(
                  label: Text(word),
                  backgroundColor: Colors.orange.shade100,
                  labelStyle: TextStyle(color: Colors.orange.shade800),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.comment, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '상세 피드백',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...widget.history.detailedFeedback.map((feedback) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 16, color: Colors.black, fontFamily: 'Pretendard', height: 1.4),
                          children: buildFeedbackSpans(feedback), // 👈 1단계에서 만든 공용 함수 호출
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb, color: Colors.amber),
                const SizedBox(width: 8),
                const Text(
                  '개선 제안',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...widget.history.suggestions.map((suggestion) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡 ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 16, color: Colors.black, fontFamily: 'Pretendard', height: 1.4),
                          children: buildFeedbackSpans(suggestion), // 👈 1단계에서 만든 공용 함수 호출
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('이 분석 기록을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiService.deletePronunciationHistory(widget.history.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기록이 삭제되었습니다.')),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentName();
  }

  Future<void> _loadCurrentName() async {
    setState(() => _isLoading = true);

    try {
      final profile = await _apiService.getUserProfile();

      if (mounted) {
        setState(() {
          _nameController.text = profile['name'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('프로필 로드 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveName() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. API를 호출하여 이름을 변경하고, 업데이트된 전체 프로필 정보를 받습니다.
      final updatedProfile = await _apiService.updateUserName(name: _nameController.text.trim());

      if (mounted) {
        // 2. 받아온 최신 프로필 정보로 앱의 전역 상태(AppState)를 업데이트합니다.
        AppState.updateFromProfile(updatedProfile);

        // 3. 사용자에게 성공 메시지를 보여줍니다.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이름이 성공적으로 변경되었습니다.')),
        );

        // 4. 모든 이전 화면(설정, 프로필 관리, 이름 수정)을 닫고 새로운 홈 화면으로 이동합니다.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (context) => HomeScreen(isAdmin: _apiService.isAdmin)
          ),
              (route) => false,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        final cleanMessage = e.message.replaceFirst(RegExp(r'^\d{3}:\s*'), '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(cleanMessage), backgroundColor: Colors.red),
        );
      }
    } finally {
      // 화면 이동이 일어나므로, 이 부분은 실행되지 않을 수 있습니다.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('이름 수정'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveName,
            child: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('저장'),
          ),
        ],
      ),
      body: _isLoading && _nameController.text.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '이름',
                prefixIcon: Icon(Icons.person),
                hintText: '예) 홍길동',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '이름을 입력해주세요';
                }
                if (value.trim().length < 2) {
                  return '이름은 최소 2자 이상이어야 합니다';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

class PostEditScreen extends StatefulWidget {
  final Post post;

  const PostEditScreen({super.key, required this.post});

  @override
  State<PostEditScreen> createState() => _PostEditScreenState();
}

class _PostEditScreenState extends State<PostEditScreen> {
  final ApiService _apiService = ApiService();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 기존 게시글의 제목과 내용으로 컨트롤러를 초기화합니다.
    _titleController = TextEditingController(text: widget.post.title);
    _contentController = TextEditingController(text: widget.post.content);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submitUpdate() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 모두 입력해주세요.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _apiService.updatePost(
        postId: widget.post.id,
        title: _titleController.text,
        content: _contentController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시글이 성공적으로 수정되었습니다!')),
        );
        Navigator.pop(context, true); // 수정 성공 시 true를 반환
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글 수정'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submitUpdate,
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('완료'),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '제목'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _contentController,
                decoration: const InputDecoration(labelText: '내용', alignLabelWithHint: true),
                maxLines: null,
                expands: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GrammarHistoryScreen extends StatefulWidget {
  const GrammarHistoryScreen({super.key});

  @override
  State<GrammarHistoryScreen> createState() => _GrammarHistoryScreenState();
}

class _GrammarHistoryScreenState extends State<GrammarHistoryScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<GrammarHistory>> _historyFuture;
  late Future<GrammarStatistics> _statsFuture;
  List<GrammarHistory> _historyList = [];

  final Map<int, bool> _expandedStates = {};
  bool _isCorrectSectionExpanded = true;
  bool _isIncorrectSectionExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _statsFuture = _apiService.getGrammarStatistics();
      _historyFuture = _apiService.getGrammarHistory().then((data) {
        _historyList = data;
        return _historyList;
      });
    });
  }

  Future<void> _toggleFavorite(GrammarHistory item) async {
    final originalStatus = item.isFavorite;
    setState(() {
      item.isFavorite = !item.isFavorite;
    });

    try {
      await _apiService.updateGrammarFavoriteStatus(historyId: item.id, isFavorite: item.isFavorite);
    } catch (e) {
      setState(() {
        item.isFavorite = originalStatus;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('즐겨찾기 변경에 실패했습니다.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('문법 학습 이력'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      // [수정] FutureBuilder를 Body 최상단으로 이동시켜 버튼과 리스트가 함께 데이터를 사용하도록 변경
      body: FutureBuilder<List<dynamic>>(
        // stats와 history를 동시에 로드
        future: Future.wait([_statsFuture, _historyFuture]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('데이터 로딩 오류: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('데이터가 없습니다.'));
          }

          // Future.wait 결과를 각각 변수에 할당
          final GrammarStatistics stats = snapshot.data![0];
          final List<GrammarHistory> history = snapshot.data![1];
          final incorrectItems = history.where((item) => !item.isCorrect).toList();

          return Column(
            children: [
              // 통계 카드
              _buildStatisticsCard(stats),
              // [신규] 오답 노트 버튼
              _buildIncorrectNoteButton(context, incorrectItems),
              const Divider(height: 1),
              // 히스토리 목록
              Expanded(child: _buildHistoryList(history)),
            ],
          );
        },
      ),
    );
  }

  // [수정] 통계 카드는 이제 파라미터로 데이터를 받음
  Widget _buildStatisticsCard(GrammarStatistics stats) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0), // 아래쪽 마진 제거
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('전체 통계', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('총 학습', stats.totalCount.toDouble(), '회', Colors.black87),
                _buildStatItem('정답', stats.correctCount.toDouble(), '회', Colors.green),
                _buildStatItem('오답', stats.incorrectCount.toDouble(), '회', Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // [신규] 오답 노트 버튼 위젯
  Widget _buildIncorrectNoteButton(BuildContext context, List<GrammarHistory> incorrectItems) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.edit_note),
        label: const Text('오답 노트 '),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.blue.shade700,
          side: BorderSide(color: Colors.blue.shade200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => IncorrectGrammarHistoryScreen(incorrectItems: incorrectItems),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, double value, String unit, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Text(
          '${value.toInt()}$unit',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  // [수정] 히스토리 목록 위젯은 이제 파라미터로 데이터를 받음
  Widget _buildHistoryList(List<GrammarHistory> history) {
    if (history.isEmpty) {
      return const Center(child: Text('문법 학습 기록이 없습니다.'));
    }

    final correctItems = history.where((item) => item.isCorrect).toList();
    final incorrectItems = history.where((item) => !item.isCorrect).toList();

    return RefreshIndicator(
      onRefresh: () async => _loadData(),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: [
          _buildSectionHeader(
            title: '정답',
            count: correctItems.length,
            isExpanded: _isCorrectSectionExpanded,
            onTap: () => setState(() => _isCorrectSectionExpanded = !_isCorrectSectionExpanded),
          ),
          if (_isCorrectSectionExpanded)
            if (correctItems.isEmpty)
              const Padding(padding: EdgeInsets.all(16.0), child: Center(child: Text('정답 기록이 없습니다.')))
            else
              ...correctItems.map((item) => _buildHistoryCard(item)),

          _buildSectionHeader(
            title: '오답',
            count: incorrectItems.length,
            isExpanded: _isIncorrectSectionExpanded,
            onTap: () => setState(() => _isIncorrectSectionExpanded = !_isIncorrectSectionExpanded),
          ),
          if (_isIncorrectSectionExpanded)
            if (incorrectItems.isEmpty)
              const Padding(padding: EdgeInsets.all(16.0), child: Center(child: Text('오답 기록이 없습니다.')))
            else
            // [수정] take(3) 제거, 모든 오답을 보여줌
              ...incorrectItems.map((item) => _buildHistoryCard(item)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required int count,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0),
        child: Row(
          children: [
            Text('$title ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('($count)', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
            const Spacer(),
            Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(GrammarHistory item) {
    final isExpanded = _expandedStates[item.id] ?? false;
    final bool wasCorrect = item.isCorrect;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (item.grammarFeedback.isNotEmpty && !wasCorrect) {
                        setState(() {
                          _expandedStates[item.id] = !isExpanded;
                        });
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("제출한 답안", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 16, color: Colors.black, fontFamily: 'Pretendard', height: 1.4),
                            children: _buildTextSpans(item.transcribedText, wasCorrect ? Colors.green : Colors.red),
                          ),
                        ),
                        if (!wasCorrect) ...[
                          const SizedBox(height: 12),
                          const Text("정답", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 16, color: Colors.black, fontFamily: 'Pretendard', height: 1.4),
                              children: _buildTextSpans(item.correctedText, Colors.green),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    item.isFavorite ? Icons.star : Icons.star_border,
                    color: item.isFavorite ? Colors.amber : Colors.grey,
                  ),
                  onPressed: () => _toggleFavorite(item),
                ),
              ],
            ),
          ),
          if (item.grammarFeedback.isNotEmpty && !wasCorrect)
            AnimatedCrossFade(
              firstChild: Container(),
              secondChild: Container(
                color: Colors.grey.shade50,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("해설", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...item.grammarFeedback.map((fb) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black, fontFamily: 'Pretendard'), // 기본 스타일
                          children: buildFeedbackSpans("• $fb"), // 👈 1단계에서 만든 공용 함수 호출
                        ),
                      ),
                    )),
                  ],
                ),
              ),
              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
        ],
      ),
    );
  }

  List<TextSpan> _buildTextSpans(String text, Color highlightColor) {
    final List<TextSpan> spans = [];
    final RegExp exp = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;

    for (final Match match in exp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(fontWeight: FontWeight.bold, color: highlightColor, backgroundColor: highlightColor.withOpacity(0.1)),
      ));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }
}

class WordEditScreen extends StatefulWidget {
  final UserWord word; // 수정할 단어 데이터를 전달받음
  const WordEditScreen({super.key, required this.word});

  @override
  State<WordEditScreen> createState() => _WordEditScreenState();
}

class _WordEditScreenState extends State<WordEditScreen> {
  final _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _wordController;
  late final TextEditingController _definitionController;
  late final TextEditingController _pronunciationController;
  late final TextEditingController _exampleController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 전달받은 단어 데이터로 텍스트 필드를 초기화합니다.
    _wordController = TextEditingController(text: widget.word.word);
    _definitionController = TextEditingController(text: widget.word.definition);
    _pronunciationController = TextEditingController(text: widget.word.pronunciation);
    _exampleController = TextEditingController(text: widget.word.englishExample);
  }

  @override
  void dispose() {
    _wordController.dispose();
    _definitionController.dispose();
    _pronunciationController.dispose();
    _exampleController.dispose();
    super.dispose();
  }

  Future<void> _saveWord() async {
    if (!_formKey.currentState!.validate()) return; // 유효성 검사

    setState(() => _isLoading = true);
    try {
      await _apiService.updateWordContent(
        wordId: widget.word.id,
        word: _wordController.text,
        definition: _definitionController.text,
        pronunciation: _pronunciationController.text,
        englishExample: _exampleController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('단어가 성공적으로 수정되었습니다!')),
        );
        // 수정 성공 시 true 값을 반환하며 이전 화면으로 돌아갑니다.
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('수정 실패: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('단어 수정'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveWord,
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('저장'),
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _wordController,
              decoration: const InputDecoration(labelText: '단어'),
              validator: (value) => (value?.isEmpty ?? true) ? '단어를 입력해주세요.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _definitionController,
              decoration: const InputDecoration(labelText: '뜻'),
              validator: (value) => (value?.isEmpty ?? true) ? '뜻을 입력해주세요.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pronunciationController,
              decoration: const InputDecoration(labelText: '발음'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _exampleController,
              decoration: const InputDecoration(labelText: '예문'),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class PlanTemplateScreen extends StatefulWidget {
  const PlanTemplateScreen({super.key});

  @override
  State<PlanTemplateScreen> createState() => _PlanTemplateScreenState();
}

class _PlanTemplateScreenState extends State<PlanTemplateScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<dynamic>> _templatesFuture;
  String? _selectedTemplateId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _templatesFuture = _apiService.getPlanTemplates();
  }

  Future<void> _startWithSelectedPlan() async {
    if (_selectedTemplateId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시작할 학습 계획을 선택해주세요.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final newProfile = await _apiService.selectPlanTemplate(templateId: _selectedTemplateId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('학습 계획이 설정되었습니다!')),
        );
        // 성공 시, 변경된 프로필 정보를 가지고 이전 화면으로 돌아갑니다.
        Navigator.pop(context, newProfile);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('추천 학습 계획')),
      body: FutureBuilder<List<dynamic>>(
        future: _templatesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('오류: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('추천 계획을 불러올 수 없습니다.'));
          }

          final templates = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: RadioListTile<String>(
                        contentPadding: const EdgeInsets.all(12),
                        title: Text(template['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(template['description']),
                        ),
                        value: template['id'],
                        groupValue: _selectedTemplateId,
                        onChanged: (value) {
                          setState(() => _selectedTemplateId = value);
                        },
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ElevatedButton(
                  onPressed: _isLoading || _selectedTemplateId == null ? null : _startWithSelectedPlan,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('이 계획으로 시작하기'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PasswordChangeScreen extends StatefulWidget {
  const PasswordChangeScreen({super.key});

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 비밀번호가 일치하지 않습니다.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _apiService.updatePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비밀번호가 성공적으로 변경되었습니다.')),
        );

        // ✅ 변경: 단순히 pop() 대신 메인화면으로 이동
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (context) => HomeScreen(isAdmin: _apiService.isAdmin)
          ),
              (route) => false, // 모든 이전 라우트 제거
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 변경')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            TextFormField(
              controller: _currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '현재 비밀번호'),
              validator: (value) => (value?.isEmpty ?? true) ? '현재 비밀번호를 입력해주세요.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '새 비밀번호'),
              validator: (value) {
                if (value == null || value.isEmpty) return '새 비밀번호를 입력해주세요.';
                if (value.length < 8) return '비밀번호는 8자 이상이어야 합니다.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
              validator: (value) => (value?.isEmpty ?? true) ? '새 비밀번호를 다시 입력해주세요.' : null,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _changePassword,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('변경하기'),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountDeleteScreen extends StatefulWidget {
  const AccountDeleteScreen({super.key});

  @override
  State<AccountDeleteScreen> createState() => _AccountDeleteScreenState();
}

class _AccountDeleteScreenState extends State<AccountDeleteScreen> {
  final _apiService = ApiService();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호를 입력해주세요.'), backgroundColor: Colors.red),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('정말로 탈퇴하시겠습니까?'),
        content: const Text('회원 탈퇴 시 모든 학습 기록이 영구적으로 삭제되며 복구할 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _apiService.deleteAccount(password: _passwordController.text);

      if (mounted) {
        // 탈퇴 성공 시 로컬 데이터도 모두 삭제
        await _apiService.logout();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회원 탈퇴가 완료되었습니다.')),
        );
        // 앱의 초기 화면으로 이동
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => InitialScreen()),
              (route) => false,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원 탈퇴')),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 60),
          const SizedBox(height: 16),
          const Text(
            '회원 탈퇴 안내',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 16),
          const Text(
            '회원 탈퇴를 진행하려면 현재 계정의 비밀번호를 입력해주세요. 탈퇴 후에는 계정과 관련된 모든 데이터를 복구할 수 없습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '비밀번호 확인',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isLoading ? null : _deleteAccount,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('회원 탈퇴'),
          ),
        ],
      ),
    );
  }
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final ApiService _apiService = ApiService();
  late Future<LearningProgress> _progressFuture;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  void _loadProgress() {
    setState(() {
      _progressFuture = _apiService.getTodayLearningProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘의 학습 진척도'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProgress,
          ),
        ],
      ),
      body: FutureBuilder<LearningProgress>(
        future: _progressFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('진척도 데이터를 불러오는 데 실패했습니다.\n${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('데이터가 없습니다.'));
          }

          final progressData = snapshot.data!;

          return RefreshIndicator(
            onRefresh: () async => _loadProgress(),
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildOverallProgress(progressData.overallProgress),
                const SizedBox(height: 24),
                _buildDetailProgressCard(progressData),
                const SizedBox(height: 16),
                _buildFeedbackCard(progressData.feedback),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverallProgress(double overallProgress) {
    return Column(
      children: [
        SizedBox(
          width: 150,
          height: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: overallProgress,
                strokeWidth: 12,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              Center(
                child: Text(
                  '${(overallProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '전체 목표 달성률',
          style: TextStyle(fontSize: 18, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildDetailProgressCard(LearningProgress data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('학습 방식별 진척도', style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            _buildProgressIndicator(
              '회화',
              data.conversation,
              '분',
              Icons.chat_bubble_outline,
              Colors.orange,
            ),
            const SizedBox(height: 20),
            _buildProgressIndicator(
              '문법',
              data.grammar,
              '회',
              Icons.menu_book_outlined,
              Colors.blue,
            ),
            const SizedBox(height: 20),
            _buildProgressIndicator(
              '발음',
              data.pronunciation,
              '회',
              Icons.mic_none,
              Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(
      String title,
      ProgressDetail detail,
      String unit,
      IconData icon,
      Color color,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(
              '${detail.achieved} / ${detail.goal} $unit',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: detail.progress,
          minHeight: 10,
          backgroundColor: color.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          borderRadius: BorderRadius.circular(5),
        ),
      ],
    );
  }

  Widget _buildFeedbackCard(String feedback) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '학습 진척도 피드백',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(feedback, style: const TextStyle(height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(3, (index) {
        return FadeTransition(
          opacity: DelayTween(
            begin: 0.2,
            end: 1.0,
            delay: index * 0.3, // 각 점이 순차적으로 깜빡이도록 딜레이
          ).animate(_controller),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }
}

// 애니메이션을 위한 Helper 클래스
class DelayTween extends Tween<double> {
  final double delay;

  DelayTween({double? begin, double? end, required this.delay})
      : super(begin: begin, end: end);

  @override
  double lerp(double t) {
    return super.lerp((t - delay).clamp(0.0, 1.0));
  }
}

class StudyGroupRequestsScreen extends StatefulWidget {
  final int groupId;
  const StudyGroupRequestsScreen({super.key, required this.groupId});

  @override
  State<StudyGroupRequestsScreen> createState() => _StudyGroupRequestsScreenState();
}

class _StudyGroupRequestsScreenState extends State<StudyGroupRequestsScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<StudyGroupJoinRequest>> _requestsFuture;

  final Set<int> _processingRequests = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  void _loadRequests() {
    setState(() {
      _requestsFuture = _apiService.getJoinRequests(widget.groupId);
    });
  }

  Future<void> _processRequest(int requestId, bool isApproved) async {
    if (_processingRequests.contains(requestId)) return;
    setState(() => _processingRequests.add(requestId));

    try {
      final message = isApproved
          ? await _apiService.approveJoinRequest(widget.groupId, requestId)
          : await _apiService.rejectJoinRequest(widget.groupId, requestId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)));
        _loadRequests();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingRequests.remove(requestId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('가입 요청 관리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _loadRequests,
          ),
        ],
      ),
      body: FutureBuilder<List<StudyGroupJoinRequest>>(
        future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('오류: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('새로운 가입 요청이 없습니다.'));
          }
          final requests = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _loadRequests(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final request = requests[index];
                final isProcessing = _processingRequests.contains(request.requestId);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(request.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${request.requestedAt.month}월 ${request.requestedAt.day}일 요청'),
                    trailing: isProcessing
                        ? const Padding(
                      padding: EdgeInsets.only(right: 40),
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    )
                        : ButtonBar( // Row 대신 안정적인 ButtonBar 사용
                      mainAxisSize: MainAxisSize.min,
                      buttonPadding: const EdgeInsets.symmetric(horizontal: 4),
                      children: [
                        TextButton(
                          onPressed: () => _processRequest(request.requestId, false),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('거절'),
                        ),
                        ElevatedButton(
                          onPressed: () => _processRequest(request.requestId, true),
                          child: const Text('승인'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class WordSearchResultsScreen extends StatefulWidget {
  final String searchQuery;

  const WordSearchResultsScreen({super.key, required this.searchQuery});

  @override
  State<WordSearchResultsScreen> createState() => _WordSearchResultsScreenState();
}

class _WordSearchResultsScreenState extends State<WordSearchResultsScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<UserWord>> _resultsFuture;

  @override
  void initState() {
    super.initState();
    _resultsFuture = _apiService.searchAllWords(widget.searchQuery);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("'${widget.searchQuery}' 검색 결과"),
      ),
      body: FutureBuilder<List<UserWord>>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('검색 중 오류가 발생했습니다: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('검색 결과가 없습니다.'));
          }

          final words = snapshot.data!;
          // WordbookDetailScreen의 UI와 유사하게 검색 결과를 보여줍니다.
          return ListView.builder(
            padding: const EdgeInsets.all(12.0),
            itemCount: words.length,
            itemBuilder: (context, index) {
              final word = words[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(word.word, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(word.definition),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      _createSlideRoute(
                        WordDetailPagerScreen(
                          words: words,         // 검색된 단어 목록 전달
                          initialIndex: index,  // 현재 탭한 단어의 인덱스 전달
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class WordDetailContent extends StatelessWidget {
  final UserWord word;

  const WordDetailContent({super.key, required this.word});

  @override
  Widget build(BuildContext context) {
    // Scaffold와 AppBar를 제거하고 내용만 남깁니다.
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Text(word.word, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (word.pronunciation != null && word.pronunciation!.isNotEmpty)
          Text(word.pronunciation!, style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
        const Divider(height: 32),
        const Text('뜻', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Text(word.definition, style: const TextStyle(fontSize: 18, height: 1.5)),
        const SizedBox(height: 24),
        const Text('예문', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Text(
          word.englishExample ?? '등록된 예문이 없습니다.',
          style: TextStyle(
            fontSize: 18,
            height: 1.5,
            fontStyle: FontStyle.italic,
            color: Colors.blue.shade800,
          ),
        ),
      ],
    );
  }
}
// ▲▲▲ 수정 완료 ▲▲▲

// ▼▼▼ [수정 2/4] 스와이프 기능을 담당할 'WordDetailPagerScreen' 위젯을 새로 추가 ▼▼▼
class WordDetailPagerScreen extends StatefulWidget {
  final List<UserWord> words;
  final int initialIndex;

  const WordDetailPagerScreen({
    super.key,
    required this.words,
    required this.initialIndex,
  });

  @override
  State<WordDetailPagerScreen> createState() => _WordDetailPagerScreenState();
}

class _WordDetailPagerScreenState extends State<WordDetailPagerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 제목에 현재 보고 있는 단어와 전체 개수를 표시
        title: Text('${_currentIndex + 1} / ${widget.words.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.words.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          // 각 페이지마다 WordDetailContent 위젯을 사용하여 단어 정보를 표시
          return WordDetailContent(word: widget.words[index]);
        },
      ),
    );
  }
}

class ChallengeCreateScreen extends StatefulWidget {
  final int groupId;
  const ChallengeCreateScreen({super.key, required this.groupId});

  @override
  State<ChallengeCreateScreen> createState() => _ChallengeCreateScreenState();
}

class _ChallengeCreateScreenState extends State<ChallengeCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController(text: '7');

  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _createChallenge() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // 수정된 API 함수 호출
      await _apiService.createGroupChallenge(
        groupId: widget.groupId,
        title: _titleController.text,
        description: _descriptionController.text,
        durationDays: int.parse(_durationController.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('새로운 챌린지가 생성되었습니다!')));
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('오류: ${e.message}'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 챌린지 만들기')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                  labelText: '챌린지 목표 *', hintText: '예: 자막 없이 영화 한 편 보기'),
              validator: (v) => (v?.isEmpty ?? true) ? '목표를 입력하세요.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: '챌린지 설명 (선택)',
                  alignLabelWithHint: true,
                  hintText: '어떻게 인증할지 등 구체적인 내용을 적어주세요.'),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _durationController,
              decoration: const InputDecoration(labelText: '챌린지 기간 (일) *'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return '기간을 입력하세요.';
                if (int.tryParse(v) == null || int.parse(v) <= 0)
                  return '1일 이상을 입력하세요.';
                return null;
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _createChallenge,
              child: _isLoading ? const CircularProgressIndicator(
                  color: Colors.white) : const Text('챌린지 시작하기'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChallengeEditScreen extends StatefulWidget {
  final GroupChallenge challenge;
  const ChallengeEditScreen({super.key, required this.challenge});

  @override
  State<ChallengeEditScreen> createState() => _ChallengeEditScreenState();
}

class _ChallengeEditScreenState extends State<ChallengeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.challenge.title);
    _descriptionController = TextEditingController(text: widget.challenge.description);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveChallenge() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // API 서비스 함수는 이미 title과 description만 받도록 수정되어 있습니다.
      await _apiService.updateGroupChallenge(
        challengeId: widget.challenge.id,
        title: _titleController.text,
        description: _descriptionController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('챌린지가 수정되었습니다.')));
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: ${e.message}'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('챌린지 수정')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '챌린지 이름 *'),
              validator: (v) => (v?.isEmpty ?? true) ? '이름을 입력하세요.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: '챌린지 설명 (선택)', alignLabelWithHint: true),
              maxLines: 4,
            ),
            const SizedBox(height: 32),
            // 오류가 발생하던 ListTile 부분들을 삭제하고 저장 버튼만 남깁니다.
            ElevatedButton(
              onPressed: _isLoading ? null : _saveChallenge,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('수정 완료'),
            ),
          ],
        ),
      ),
    );
  }
}

class PointItem {
  final String name;
  final String description;
  final int cost;

  const PointItem({
    required this.name,
    required this.description,
    required this.cost,
  });
}

// ▼▼▼ [신규] 포인트 교환소 화면 위젯 ▼▼▼
class PointExchangeScreen extends StatefulWidget {
  const PointExchangeScreen({super.key});

  @override
  State<PointExchangeScreen> createState() => _PointExchangeScreenState();
}

class _PointExchangeScreenState extends State<PointExchangeScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  // 교환 가능한 아이템 목록 (임시 데이터)
  final List<Map<String, dynamic>> _categories = [
    {'name': '카페/베이커리', 'icon': Icons.local_cafe_outlined, 'image': 'assets/cafe.png'}, // 이미지가 있으면 이미지 사용
    {'name': '이마트24', 'icon': Icons.shopping_cart_outlined, 'image': null}, // 이미지가 없으면 아이콘 사용
    {'name': '외식', 'icon': Icons.restaurant_outlined, 'image': 'assets/dining.png'},
    {'name': '편의점', 'icon': Icons.storefront_outlined, 'image': 'assets/convenience.png'},
    {'name': '뷰티', 'icon': Icons.face_retouching_natural_outlined, 'image': 'assets/beauty.png'},
    {'name': '문화생활', 'icon': Icons.theaters_outlined, 'image': 'assets/culture.png'},
  ];

  @override
  void initState() {
    super.initState();
    // 화면이 시작될 때 최신 사용자 정보를 불러와 포인트를 갱신합니다.
    _loadUserProfile();
  }

  String _formatPoints(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
    );
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    try {
      // 1. 서버에서 최신 프로필 정보를 가져옵니다.
      final userProfile = await _apiService.getUserProfile();

      if (mounted) {
        // 2. 서버에서 받은 데이터로 AppState를 '직접' 업데이트합니다.
        //    (기존의 AppState 값으로 덮어쓰는 잘못된 로직을 제거했습니다.)
        setState(() {
          AppState.updateFromProfile(userProfile);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('최신 포인트 정보를 불러오는 데 실패했습니다.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 교환 버튼을 눌렀을 때 실행되는 함수
  Future<void> _handleExchange(PointItem item) async {
    // 1. 포인트 잔액 확인
    if (AppState.points.value < item.cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 포인트가 부족합니다.'), backgroundColor: Colors.orange),
      );
      return;
    }

    // 2. 사용자에게 교환 재확인 받기
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('포인트 교환'),
        content: Text("'${item.name}' 아이템을 ${item.cost} 포인트로 교환하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('교환')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // 3. API 호출 (사용한 포인트는 음수로 보냄)
      final response = await _apiService.executePointTransaction(
        amount: -item.cost,
        reason: "아이템 교환: ${item.name}",
      );

      // 4. 성공 시, AppState와 화면 업데이트
      if (mounted) {
        final newPoints = response['final_points'];
        if (newPoints != null && newPoints is int) {
          setState(() {
            AppState.points.value = newPoints;
          });
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('✅ 교환 완료! 남은 포인트: $newPoints'))
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('포인트 교환소'),
        actions: [
          // ▼▼▼ [수정] GestureDetector로 전체를 감싸서 탭 가능하게 만듭니다 ▼▼▼
          GestureDetector(
            onTap: () {
              // 탭하면 PointHistoryScreen으로 이동
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PointHistoryScreen()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: AppState.points,
                  builder: (context, currentPoints, child) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text('P', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // --- ▼▼▼ 여기가 수정된 부분입니다 ▼▼▼ ---
                        Text(
                          _formatPoints(currentPoints), // 쉼표 포매팅 함수 적용
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                        ),
                        // --- ▲▲▲ 여기가 수정된 부분입니다 ▲▲▲ ---
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // --- 카테고리 그리드 UI ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // 한 줄에 2개씩
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0, // 정사각형 비율
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                return _buildCategoryCard(
                  name: category['name'],
                  icon: category['icon'],
                  imagePath: category['image'],
                  onTap: () {
                    // 해당 카테고리의 아이템 목록을 가져옵니다.
                    final items = categoryItems[category['name']] ?? [];

                    // 새로운 화면(PointCategoryItemsScreen)으로 이동합니다.
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PointCategoryItemsScreen(
                          categoryName: category['name'],
                          items: items,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // --- 로딩 오버레이 ---
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

// --- 새 위젯: 카테고리 카드 ---
  Widget _buildCategoryCard({
    required String name,
    required IconData icon,
    String? imagePath, // 이미지 경로 (선택 사항)
    required VoidCallback onTap,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias, // InkWell 효과가 Card 밖으로 나가지 않도록
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 이미지가 있으면 이미지를, 없으면 아이콘을 표시
            imagePath != null
                ? Image.asset(
              imagePath,
              height: 60, // 이미지 크기 조절
              width: 60,
              fit: BoxFit.contain, // 이미지가 잘리지 않도록
              errorBuilder: (context, error, stackTrace) {
                // 이미지 로딩 실패 시 아이콘 표시
                return Icon(icon, size: 50, color: Colors.green.shade700);
              },
            )
                : Icon(icon, size: 50, color: Colors.green.shade700),
            const SizedBox(height: 12),
            Text(
              name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // 보유 포인트 카드 위젯
  Widget _buildPointBalanceCard() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Icon(Icons.monetization_on, color: Colors.green.shade700, size: 40),
            const SizedBox(width: 16),
            const Text('보유 포인트', style: TextStyle(fontSize: 16)),
            const Spacer(),
            ValueListenableBuilder<int>(
              valueListenable: AppState.points, // AppState.points의 변화를 감시
              builder: (context, currentPoints, child) {
                // 값이 바뀔 때마다 이 부분이 새로 그려집니다.
                return Text(
                  '$currentPoints P',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 각 아이템 카드 위젯
  Widget _buildItemCard(PointItem item) {
    final bool canAfford = AppState.points.value >= item.cost;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(item.description, style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Text(
                    '${item.cost} P',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: canAfford ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: canAfford && !_isLoading ? () => _handleExchange(item) : null,
              child: const Text('교환'),
            ),
          ],
        ),
      ),
    );
  }
}

class IncorrectGrammarHistoryScreen extends StatefulWidget {
  final List<GrammarHistory> incorrectItems;

  const IncorrectGrammarHistoryScreen({super.key, required this.incorrectItems});

  @override
  State<IncorrectGrammarHistoryScreen> createState() => _IncorrectGrammarHistoryScreenState();
}

class _IncorrectGrammarHistoryScreenState extends State<IncorrectGrammarHistoryScreen> {
  // GrammarHistoryScreen의 위젯들을 재사용하기 위해 GlobalKey 대신 직접 인스턴스 생성
  final _historyScreenState = _GrammarHistoryScreenState();
  late List<GrammarHistory> _currentIncorrectItems;

  @override
  void initState() {
    super.initState();
    _currentIncorrectItems = widget.incorrectItems;
  }

  // 즐겨찾기 상태를 토글하는 함수
  Future<void> _toggleFavorite(GrammarHistory item) async {
    // 이전 화면의 함수를 직접 호출
    await _historyScreenState._toggleFavorite(item);
    // UI 갱신을 위해 상태 변경
    setState(() {
      // 리스트 내 아이템의 상태가 변경되었음을 알려줌
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('오답 노트'),
      ),
      body: _currentIncorrectItems.isEmpty
          ? const Center(child: Text('오답 기록이 없습니다.'))
          : ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        itemCount: _currentIncorrectItems.length,
        itemBuilder: (context, index) {
          // GrammarHistoryScreen에 있던 _buildHistoryCard 함수를 직접 호출하여 재사용
          return _buildHistoryCard(_currentIncorrectItems[index]);
        },
      ),
    );
  }

  // _GrammarHistoryScreenState에 있던 UI 빌딩 함수들을 그대로 가져와서 사용합니다.
  Widget _buildHistoryCard(GrammarHistory item) {
    final isExpanded = _historyScreenState._expandedStates[item.id] ?? false;
    final bool wasCorrect = item.isCorrect;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (item.grammarFeedback.isNotEmpty && !wasCorrect) {
                        setState(() {
                          _historyScreenState._expandedStates[item.id] = !isExpanded;
                        });
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("제출한 답안", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 16, color: Colors.black, fontFamily: 'Pretendard', height: 1.4),
                            children: _buildTextSpans(item.transcribedText, Colors.red),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text("정답", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 16, color: Colors.black, fontFamily: 'Pretendard', height: 1.4),
                            children: _buildTextSpans(item.correctedText, Colors.green),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    item.isFavorite ? Icons.star : Icons.star_border,
                    color: item.isFavorite ? Colors.amber : Colors.grey,
                  ),
                  onPressed: () => _toggleFavorite(item),
                ),
              ],
            ),
          ),
          if (item.grammarFeedback.isNotEmpty && !wasCorrect)
            AnimatedCrossFade(
              firstChild: Container(),
              secondChild: Container(
                color: Colors.grey.shade50,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("해설", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...item.grammarFeedback.map((fb) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: RichText(
                        text: TextSpan(
                          // RichText에 기본 스타일 적용
                          style: const TextStyle(
                            fontSize: 14, // 기본 Text 위젯과 폰트 크기 맞춤
                            color: Colors.black,
                            fontFamily: 'Pretendard',
                            height: 1.5,
                          ),
                          children: buildFeedbackSpans("• $fb"), // 공용 함수 호출
                        ),
                      ),
                    )),
                  ],
                ),
              ),
              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
        ],
      ),
    );
  }

  List<TextSpan> _buildTextSpans(String text, Color highlightColor) {
    final List<TextSpan> spans = [];
    final RegExp exp = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;

    for (final Match match in exp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(fontWeight: FontWeight.bold, color: highlightColor, backgroundColor: highlightColor.withOpacity(0.1)),
      ));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }
}

class PolicyViewScreen extends StatelessWidget {
  final String title;
  final String content;

  const PolicyViewScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Text(content, style: const TextStyle(fontSize: 15, height: 1.5)),
      ),
    );
  }
}

// 약관 내용 예시 텍스트 (실제 서비스에서는 전체 내용을 채워야 합니다)
const String termsOfServiceContent = """
제1장 총칙

제1조 (목적)
이 약관은 Learning App(이하 "회사")가 제공하는 다국어 언어 학습 애플리케이션 및 관련 제반 서비스(이하 "서비스")의 이용과 관련하여 회사와 회원과의 권리, 의무 및 책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.

제2조 (정의)
이 약관에서 사용하는 용어의 정의는 다음과 같습니다.
1. "서비스"라 함은 구현되는 단말기(PC, TV, 휴대형단말기 등의 각종 유무선 장치를 포함)와 상관없이 "회원"이 이용할 수 있는 다국어 언어 학습 관련 제반 서비스를 의미합니다.
2. "회원"이라 함은 회사의 "서비스"에 접속하여 이 약관에 따라 "회사"와 이용계약을 체결하고 "회사"가 제공하는 "서비스"를 이용하는 고객을 말합니다.
3. "아이디(ID)"라 함은 "회원"의 식별과 "서비스" 이용을 위하여 "회원"이 정하고 "회사"가 승인하는 문자와 숫자의 조합을 의미합니다.
4. "비밀번호"라 함은 "회원"이 부여 받은 "아이디"와 일치되는 "회원"임을 확인하고 비밀보호를 위해 "회원" 자신이 정한 문자 또는 숫자의 조합을 의미합니다.
5. "게시물"이라 함은 "회원"이 "서비스"를 이용함에 있어 "서비스상"에 게시한 부호ㆍ문자ㆍ음성ㆍ화상 또는 동영상 등의 정보 형태의 글, 사진, 동영상 및 각종 파일과 링크 등을 의미합니다.

제3조 (약관의 게시와 개정)
1. "회사"는 이 약관의 내용을 "회원"이 쉽게 알 수 있도록 서비스 초기 화면에 게시합니다.
2. "회사"는 "약관의규제에관한법률", "정보통신망이용촉진및정보보호등에관한법률(이하 "정보통신망법")" 등 관련법을 위배하지 않는 범위에서 이 약관을 개정할 수 있습니다.
3. "회사"가 약관을 개정할 경우에는 적용일자 및 개정사유를 명시하여 현행약관과 함께 제1항의 방식에 따라 그 개정약관의 적용일자 7일 전부터 적용일자 전일까지 공지합니다. 다만, 회원에게 불리한 약관의 개정의 경우에는 공지 외에 일정기간 서비스 내 전자우편, 전자쪽지, 로그인시 동의창 등의 전자적 수단을 통해 따로 명확히 통지하도록 합니다.
4. 회사가 전항에 따라 개정약관을 공지 또는 통지하면서 회원에게 7일 기간 내에 의사표시를 하지 않으면 의사표시가 표명된 것으로 본다는 뜻을 명확하게 공지 또는 통지하였음에도 회원이 명시적으로 거부의 의사표시를 하지 아니한 경우 회원이 개정약관에 동의한 것으로 봅니다.
5. 회원이 개정약관의 적용에 동의하지 않는 경우 회사는 개정 약관의 내용을 적용할 수 없으며, 이 경우 회원은 이용계약을 해지할 수 있습니다.

제2장 서비스 이용

제4조 (서비스의 제공 등)
1. 회사는 회원에게 아래와 같은 서비스를 제공합니다.
   가. 다국어 학습 콘텐츠 제공 서비스
   나. 발음 교정 및 문법 학습 서비스
   다. 커뮤니티 서비스 (게시판, 스터디 그룹 등)
   라. 기타 "회사"가 추가 개발하거나 다른 회사와의 제휴계약 등을 통해 "회원"에게 제공하는 일체의 서비스
2. 회사는 컴퓨터 등 정보통신설비의 보수점검, 교체 및 고장, 통신두절 또는 운영상 상당한 이유가 있는 경우 서비스의 제공을 일시적으로 중단할 수 있습니다.

제5조 (회원의 의무)
1. 회원은 다음 행위를 하여서는 안 됩니다.
   가. 신청 또는 변경 시 허위내용의 등록
   나. 타인의 정보도용
   다. 회사가 게시한 정보의 변경
   라. 다른 회원의 개인정보 및 계정정보를 수집하는 행위
   마. 회사의 동의 없이 영리를 목적으로 서비스를 사용하는 행위
   바. 기타 불법적이거나 부당한 행위

제6조 (게시물의 저작권)
1. "회원"이 "서비스" 내에 게시한 "게시물"의 저작권은 해당 "게시물"의 저작자에게 귀속됩니다.
2. "회원"이 "서비스" 내에 게시하는 "게시물"은 검색결과 내지 "서비스" 및 관련 프로모션 등에 노출될 수 있으며, 해당 노출을 위해 필요한 범위 내에서는 일부 수정, 복제, 편집되어 게시될 수 있습니다. 이 경우, 회사는 저작권법 규정을 준수하며, "회원"은 언제든지 고객센터 또는 "서비스" 내 관리기능을 통해 해당 "게시물"에 대해 삭제, 검색결과 제외, 비공개 등의 조치를 취할 수 있습니다.

제3장 계약 해지 및 이용 제한

제7조 (회원 탈퇴 및 자격 상실 등)
1. 회원은 회사에 언제든지 탈퇴를 요청할 수 있으며 회사는 즉시 회원탈퇴를 처리합니다.
2. 회원이 다음 각호의 사유에 해당하는 경우, 회사는 회원자격을 제한 및 정지시킬 수 있습니다.
   가. 가입 신청 시에 허위 내용을 등록한 경우
   나. 다른 사람의 서비스 이용을 방해하거나 그 정보를 도용하는 등 전자상거래 질서를 위협하는 경우
   다. 서비스를 이용하여 법령 또는 이 약관이 금지하거나 공서양속에 반하는 행위를 하는 경우

제4장 기타

제8조 (면책조항)
1. 회사는 천재지변 또는 이에 준하는 불가항력으로 인하여 서비스를 제공할 수 없는 경우에는 서비스 제공에 관한 책임이 면제됩니다.
2. 회사는 회원의 귀책사유로 인한 서비스 이용의 장애에 대하여는 책임을 지지 않습니다.

제9조 (준거법 및 재판관할)
1. 회사와 회원 간 제기된 소송은 대한민국법을 준거법으로 합니다.
2. 회사와 회원간 발생한 분쟁에 관한 소송은 민사소송법 상의 관할법원에 제소합니다.

부칙
1. 이 약관은 2025년 10월 17일부터 적용됩니다.
""";

// ▼▼▼ [수정] 개인정보 처리방침 전체 내용 ▼▼▼
const String privacyPolicyContent = """
Learning App(이하 '회사'라 한다)는 개인정보보호법을 준수하며, 관련 법령에 의거한 개인정보처리방침을 정하여 이용자 권익 보호에 최선을 다하고 있습니다.

제1조 (개인정보의 처리 목적)
회사는 다음의 목적을 위하여 개인정보를 처리합니다. 처리하고 있는 개인정보는 다음의 목적 이외의 용도로는 이용되지 않으며, 이용 목적이 변경되는 경우에는 개인정보 보호법 제18조에 따라 별도의 동의를 받는 등 필요한 조치를 이행할 예정입니다.
1. 회원 가입 및 관리: 회원 가입의사 확인, 회원제 서비스 제공에 따른 본인 식별·인증, 회원자격 유지·관리, 서비스 부정이용 방지, 만 14세 미만 아동의 개인정보 처리 시 법정대리인의 동의여부 확인, 각종 고지·통지, 고충처리 등을 목적으로 개인정보를 처리합니다.
2. 서비스 제공: 학습 콘텐츠 제공, 맞춤 서비스 제공, 본인인증, 연령인증, 요금 결제·정산 등을 목적으로 개인정보를 처리합니다.
3. 마케팅 및 광고에의 활용: 신규 서비스(제품) 개발 및 맞춤 서비스 제공, 이벤트 및 광고성 정보 제공 및 참여기회 제공, 인구통계학적 특성에 따른 서비스 제공 및 광고 게재, 접속빈도 파악 또는 회원의 서비스 이용에 대한 통계 등을 목적으로 개인정보를 처리합니다.

제2조 (처리하는 개인정보의 항목)
회사는 다음의 개인정보 항목을 처리하고 있습니다.
1. 필수항목: 이메일, 비밀번호, 이름(닉네임)
2. 선택항목: 프로필 사진, 학습 목표, 학습 언어 등
3. 자동수집항목: 서비스 이용 기록, 접속 로그, 쿠키, 접속 IP 정보

제3조 (개인정보의 처리 및 보유 기간)
① 회사는 법령에 따른 개인정보 보유·이용기간 또는 정보주체로부터 개인정보를 수집 시에 동의 받은 개인정보 보유·이용기간 내에서 개인정보를 처리·보유합니다.
② 각각의 개인정보 처리 및 보유 기간은 다음과 같습니다.
1. 회원 가입 및 관리: 회원 탈퇴 시까지. 다만, 다음의 사유에 해당하는 경우에는 해당 사유 종료 시까지
   - 관계 법령 위반에 따른 수사·조사 등이 진행 중인 경우에는 해당 수사·조사 종료 시까지
   - 서비스 이용에 따른 채권·채무관계 잔존 시에는 해당 채권·채무관계 정산 시까지
2. 재화 또는 서비스 제공: 재화·서비스 공급완료 및 요금결제·정산 완료 시까지

제4조 (개인정보의 파기)
① 회사는 개인정보 보유기간의 경과, 처리목적 달성 등 개인정보가 불필요하게 되었을 때에는 지체없이 해당 개인정보를 파기합니다.
② 정보주체로부터 동의받은 개인정보 보유기간이 경과하거나 처리목적이 달성되었음에도 불구하고 다른 법령에 따라 개인정보를 계속 보존하여야 하는 경우에는, 해당 개인정보를 별도의 데이터베이스(DB)로 옮기거나 보관장소를 달리하여 보존합니다.
③ 개인정보 파기의 절차 및 방법은 다음과 같습니다.
1. 파기절차: 회사는 파기 사유가 발생한 개인정보를 선정하고, 회사의 개인정보 보호책임자의 승인을 받아 개인정보를 파기합니다.
2. 파기방법: 전자적 파일 형태의 정보는 기록을 재생할 수 없는 기술적 방법을 사용하며, 종이에 출력된 개인정보는 분쇄기로 분쇄하거나 소각을 통하여 파기합니다.

제5조 (정보주체와 법정대리인의 권리·의무 및 그 행사방법)
정보주체는 회사에 대해 언제든지 개인정보 열람, 정정, 삭제, 처리정지 요구 등의 권리를 행사할 수 있습니다.

제6조 (개인정보 보호책임자)
① 회사는 개인정보 처리에 관한 업무를 총괄해서 책임지고, 개인정보 처리와 관련한 정보주체의 불만처리 및 피해구제 등을 위하여 아래와 같이 개인정보 보호책임자를 지정하고 있습니다.
- 성명: OOO
- 직책: OOO
- 연락처: XXXX-XXXX
② 정보주체께서는 회사의 서비스(또는 사업)을 이용하시면서 발생한 모든 개인정보 보호 관련 문의, 불만처리, 피해구제 등에 관한 사항을 개인정보 보호책임자 및 담당부서로 문의하실 수 있습니다.

제7조 (개인정보 처리방침의 변경)
이 개인정보처리방침은 시행일로부터 적용되며, 법령 및 방침에 따른 변경내용의 추가, 삭제 및 정정이 있는 경우에는 변경사항의 시행 7일 전부터 공지사항을 통하여 고지할 것입니다.

시행일자: 2025년 10월 17일
""";

class PointHistoryScreen extends StatefulWidget {
  const PointHistoryScreen({super.key});

  @override
  State<PointHistoryScreen> createState() => _PointHistoryScreenState();
}

class _PointHistoryScreenState extends State<PointHistoryScreen> {
  final ApiService _apiService = ApiService();

  // 상태 변수
  bool _isLoading = true;
  List<PointTransaction> _allTransactions = [];
  List<PointTransaction> _filteredTransactions = [];

  // 필터 변수
  DateTime _selectedMonth = DateTime.now();
  String _filterType = 'used';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // API로부터 데이터 로드
  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final transactions = await _apiService.getPointHistory();
      if (mounted) {
        setState(() {
          _allTransactions = transactions;
          _isLoading = false;
        });
        _applyFilters(); // 로드 후 필터 적용
      }
    } catch(e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('내역 로딩 실패: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // 필터 적용 로직
  void _applyFilters() {
    setState(() {
      _filteredTransactions = _allTransactions.where((t) {
        final isSameMonth = t.createdAt.year == _selectedMonth.year && t.createdAt.month == _selectedMonth.month;
        if (!isSameMonth) return false;
        if (_filterType == 'earned') return t.amount > 0;
        if (_filterType == 'used') return t.amount < 0;
        return true;
      }).toList();
    });
  }

  // 월 선택 다이얼로그
  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: '조회할 월 선택',
      locale: const Locale('ko'),
    );
    if (picked != null && (picked.year != _selectedMonth.year || picked.month != _selectedMonth.month)) {
      setState(() {
        _selectedMonth = picked;
      });
      _applyFilters();
    }
  }

  // 숫자 포맷팅
  String _formatPoints(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('포인트 내역')),
      body: Column(
        children: [
          _buildHeader(),

          // ▼▼▼ [수정] 헤더와 필터 사이에 구분선 추가 ▼▼▼
          const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),

          _buildFilters(),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredTransactions.isEmpty
                ? const Center(child: Text('해당 월의 내역이 없습니다.'))
                : ListView.builder(
              itemCount: _filteredTransactions.length,
              itemBuilder: (context, index) {
                return _buildTransactionItem(_filteredTransactions[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- UI 빌더 헬퍼 위젯들 ---

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        // ▼▼▼ [수정] 가운데 정렬을 위해 crossAxisAlignment 추가 ▼▼▼
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('내 포인트', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: AppState.points,
            builder: (context, points, child) {
              return Text(
                '${_formatPoints(points)} P',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ▼▼▼ [수정] 월 선택 버튼 디자인 변경 ▼▼▼
          OutlinedButton(
            onPressed: () => _selectMonth(context),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Row(
              children: [
                Text(
                  '${_selectedMonth.year}년 ${_selectedMonth.month}월',
                  style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.normal),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_drop_down, color: Colors.grey.shade700),
              ],
            ),
          ),

          ToggleButtons(
            isSelected: [_filterType == 'all', _filterType == 'earned', _filterType == 'used'],
            onPressed: (index) {
              setState(() {
                if (index == 0) _filterType = 'all';
                if (index == 1) _filterType = 'earned';
                if (index == 2) _filterType = 'used';
              });
              _applyFilters();
            },
            borderRadius: BorderRadius.circular(8),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('전체')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('적립')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('사용')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(PointTransaction transaction) {
    final bool isUsage = transaction.amount < 0;
    final String date = '${transaction.createdAt.year}.${transaction.createdAt.month.toString().padLeft(2, '0')}.${transaction.createdAt.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  transaction.reason,
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${isUsage ? '' : '+'}${_formatPoints(transaction.amount)} P',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isUsage ? Colors.blue : Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- 카테고리별 상품 목록 화면 ---
class PointCategoryItemsScreen extends StatefulWidget {
  final String categoryName;
  final List<ExchangeItem> items;

  const PointCategoryItemsScreen({
    super.key,
    required this.categoryName,
    required this.items,
  });

  @override
  State<PointCategoryItemsScreen> createState() => _PointCategoryItemsScreenState();
}

class _PointCategoryItemsScreenState extends State<PointCategoryItemsScreen> {
  late List<String> _brands;
  String? _selectedBrand;

  @override
  void initState() {
    super.initState();
    // 상품 목록에서 중복되지 않는 브랜드 목록을 추출합니다.
    _brands = widget.items.map((item) => item.brand).toSet().toList();
    if (_brands.isNotEmpty) {
      _selectedBrand = _brands.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 선택된 브랜드의 상품만 필터링합니다.
    final filteredItems = _selectedBrand == null
        ? widget.items
        : widget.items.where((item) => item.brand == _selectedBrand).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
      ),
      body: Column(
        children: [
          // 브랜드 필터 버튼 UI
          if (_brands.length > 1)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 8.0,
                  children: _brands.map((brand) {
                    final isSelected = brand == _selectedBrand;
                    return ChoiceChip(
                      label: Text(brand),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedBrand = brand);
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          // 상품 목록 UI
          Expanded(
            child: filteredItems.isEmpty
                ? const Center(child: Text('이 카테고리에는 상품이 없습니다.'))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final item = filteredItems[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: Image.asset(
                      item.imagePath,
                      width: 60,
                      height: 60,
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.shade100,
                        child: Icon(Icons.image_not_supported, color: Colors.grey.shade400),
                      ),
                    ),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(item.brand),
                    trailing: Text(
                      '${item.cost} P',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.green,
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PointItemDetailScreen(item: item),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


// --- 상품 상세 정보 및 교환 화면 ---
class PointItemDetailScreen extends StatefulWidget {
  final ExchangeItem item;

  const PointItemDetailScreen({super.key, required this.item});

  @override
  State<PointItemDetailScreen> createState() => _PointItemDetailScreenState();
}

class _PointItemDetailScreenState extends State<PointItemDetailScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  Future<void> _handleExchange() async {
    if (AppState.points.value < widget.item.cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 포인트가 부족합니다.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('상품 교환'),
        content: Text("'${widget.item.name}' 상품을\n${widget.item.cost} 포인트로 교환하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('교환')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final response = await _apiService.executePointTransaction(
        amount: -widget.item.cost, // 포인트 사용은 음수
        reason: "상품 교환: ${widget.item.name}",
      );

      if (mounted) {
        final newPoints = response['final_points'] as int?;
        if (newPoints != null) {
          AppState.points.value = newPoints; // AppState의 포인트 업데이트
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ 교환 완료! 남은 포인트: $newPoints P')),
          );
          Navigator.pop(context); // 교환 성공 후 상세 화면 닫기
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAfford = AppState.points.value >= widget.item.cost;

    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  Image.asset(
                    widget.item.imagePath,
                    height: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => Container(
                      height: 200,
                      color: Colors.grey.shade100,
                      child: Icon(Icons.image_not_supported, size: 80, color: Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(widget.item.brand, style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Text(widget.item.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  Text(
                    '${widget.item.cost} P',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: canAfford && !_isLoading ? _handleExchange : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('교환하기'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChallengeSubmissionScreen extends StatefulWidget {
  final int challengeId;
  final ChallengeSubmission? submissionToEdit; // 수정할 데이터를 받을 변수 추가

  const ChallengeSubmissionScreen({
    super.key,
    required this.challengeId,
    this.submissionToEdit, // 생성자에 추가
  });

  @override
  State<ChallengeSubmissionScreen> createState() => _ChallengeSubmissionScreenState();
}

class _ChallengeSubmissionScreenState extends State<ChallengeSubmissionScreen> {
  final _apiService = ApiService();
  final _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  bool _isLoading = false;
  String? _existingImageUrl;
  bool get _isEditing => widget.submissionToEdit != null;

  @override
  void initState() {
    super.initState();
    // 수정 모드일 경우, 기존 데이터로 UI 필드를 채웁니다.
    if (_isEditing) {
      _contentController.text = widget.submissionToEdit!.proofContent ?? '';
      _existingImageUrl = widget.submissionToEdit!.proofImageUrl;
    }
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    setState(() { _imageFile = pickedFile; });
  }

  Future<void> _submit() async {
    if (_imageFile == null && _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진이나 글 중 하나는 반드시 제출해야 합니다.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_isEditing) {
        // --- 수정 로직 ---
        await _apiService.updateChallengeSubmission(
          submissionId: widget.submissionToEdit!.id,
          content: _contentController.text.trim(),
          imageFile: _imageFile,
        );
      } else {
        // --- 생성 로직 (기존과 동일) ---
        await _apiService.submitChallengeProof(
          challengeId: widget.challengeId,
          content: _contentController.text.trim(),
          imageFile: _imageFile,
        );
      }

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 인증이 성공적으로 ${_isEditing ? '수정' : '제출'}되었습니다!')),
        );
        Navigator.pop(context, true); // 성공 시 true 반환
      }
    } on ApiException catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '인증 수정하기' : '챌린지 인증하기')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _imageFile != null
                // 1. 새로 선택한 이미지가 있을 때 (오류 수정)
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(_imageFile!.path), fit: BoxFit.cover),
                )
                // 2. 기존 이미지가 있을 때
                    : _existingImageUrl != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(_existingImageUrl!, fit: BoxFit.cover),
                )
                // 3. 아무 이미지도 없을 때 (오류 수정)
                    : const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 50, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('탭하여 인증샷 올리기'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(labelText: '인증 내용 (선택)', hintText: '오늘 공부한 내용에 대해 간단히 적어주세요.', alignLabelWithHint: true),
              maxLines: 4,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(_isEditing ? '수정 완료' : '제출하기'),
            ),
          ],
        ),
      ),
    );
  }
}