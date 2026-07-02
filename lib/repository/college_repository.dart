import 'package:guidex/database/database_helper.dart';
import 'package:guidex/models/college_option.dart';
import 'package:guidex/models/final_report_response.dart';
import 'package:guidex/models/recommendation.dart';
import 'package:guidex/models/recommendation_result.dart';
import 'package:guidex/services/probability_calculator_service.dart';

class CollegeRepository {
  static final CollegeRepository _instance = CollegeRepository._internal();
  factory CollegeRepository() => _instance;
  CollegeRepository._internal();

  String _normalizeCourseForSearch(String course) {
    final raw = course.trim();
    if (raw.isEmpty) return raw;

    final normalized =
        raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

    const aliases = <String, String>{
      'cs': 'Computer Science',
      'cse': 'Computer Science',
      'computer science and engineering': 'Computer Science',
      'computer science engineering': 'Computer Science',
      'ec': 'Electronics and Communication',
      'ee': 'Electrical and Electronics',
      'ei': 'Electronics and Instrumentation',
      'it': 'Information Technology',
      'ece': 'Electronics and Communication',
      'eee': 'Electrical and Electronics',
      'ad': 'Artificial Intelligence',
      'am': 'Artificial Intelligence',
      'mech': 'Mechanical Engineering',
      'me': 'Mechanical Engineering',
      'ce': 'Civil Engineering',
      'civil': 'Civil Engineering',
      'bt': 'Biotechnology',
      'bme': 'Biomedical Engineering',
    };

    return aliases[normalized] ?? raw;
  }

  String _normalizeToken(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<List<String>> getDistricts() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT district FROM colleges WHERE district IS NOT NULL AND district != "" ORDER BY district ASC',
    );
    return maps.map((e) => e['district'] as String).toList();
  }

  Future<List<String>> getCourses() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT course_name FROM courses ORDER BY course_name ASC',
    );
    return maps.map((e) => e['course_name'] as String).toList();
  }

  Future<List<String>> getAvailableCourses({
    required String category,
    required double cutoff,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final categoryColumn = category.trim().toLowerCase();
    final validColumns = ['oc', 'bc', 'bcm', 'mbc', 'sc', 'sca', 'st'];
    final actualColumn = validColumns.contains(categoryColumn) ? categoryColumn : 'oc';
    
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT branch_name FROM cutoff_history WHERE $actualColumn <= ? ORDER BY branch_name ASC',
      [cutoff]
    );
    return maps.map((e) => e['branch_name'] as String).toList();
  }

  Future<List<CollegeOption>> getAllColleges() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT college_id, college_name, district FROM colleges ORDER BY college_name ASC',
    );
    return maps.map((e) => CollegeOption(
          collegeId: e['college_id'].toString(),
          collegeName: e['college_name'].toString(),
          district: e['district']?.toString(),
        )).toList();
  }

  Future<List<CollegeOption>> getCollegeOptions({
    required String preferredCourse,
    String? district,
    String? category,
    double? cutoff,
  }) async {
    if (preferredCourse.trim().isEmpty) {
      return const [];
    }

    final db = await DatabaseHelper.instance.database;
    final courseToken = _normalizeCourseForSearch(preferredCourse);
    
    String query = '''
      SELECT DISTINCT c.college_id, c.college_name, c.district 
      FROM colleges c 
      INNER JOIN cutoff_history cu ON c.college_id = cu.college_id 
      WHERE cu.branch_name LIKE ?
    ''';
    List<dynamic> args = ['%$courseToken%'];

    if (district != null && district.trim().isNotEmpty && district.toLowerCase() != 'any') {
      query += ' AND c.district = ?';
      args.add(district.trim());
    }

    query += ' ORDER BY c.college_name ASC';

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, args);
    return maps.map((e) => CollegeOption(
          collegeId: e['college_id'].toString(),
          collegeName: e['college_name'].toString(),
          district: e['district']?.toString(),
        )).toList();
  }

  Future<List<Recommendation>> getRecommendations({
    required String category,
    required double cutoff,
    required String interest,
    String? district,
    List<String> preferredCollegeIds = const [],
    List<String> preferredCollegeNames = const [],
  }) async {
    final db = await DatabaseHelper.instance.database;
    final courseToken = _normalizeCourseForSearch(interest);
    final categoryColumn = category.trim().toLowerCase();

    // Verify category column is valid to prevent SQL injection
    final validColumns = ['oc', 'bc', 'bcm', 'mbc', 'sc', 'sca', 'st'];
    final actualColumn = validColumns.contains(categoryColumn) ? categoryColumn : 'oc';

    String query = '''
      SELECT c.college_name, cu.branch_name, cu.$actualColumn as cutoff, c.district, c.college_type
      FROM colleges c
      INNER JOIN cutoff_history cu ON c.college_id = cu.college_id
      WHERE cu.branch_name LIKE ?
    ''';
    List<dynamic> args = ['%$courseToken%'];

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, args);
    
    List<Recommendation> allRecs = [];
    
    for (var map in maps) {
      final collegeName = map['college_name'] as String;
      final courseName = map['branch_name'] as String;
      final collCutoff = (map['cutoff'] as num?)?.toDouble() ?? 0.0;
      final dist = map['district'] as String?;
      final cType = map['college_type'] as String?;
      
      final probResult = ProbabilityCalculatorService.calculateProbability(
        collegeName: collegeName,
        courseName: courseName,
        studentCutoff: cutoff,
        collegeCutoff: collCutoff > 0 ? collCutoff : 100.0,
        category: category,
        isPreferredCollege: false,
        isLocationMatch: district != null && dist != null && dist.toLowerCase() == district.toLowerCase(),
        hostelAvailable: true,
      );

      allRecs.add(Recommendation(
        collegeName: collegeName,
        courseName: courseName,
        cutoff: collCutoff,
        maxCutoff: collCutoff, // SQLite might not have max/opening cutoff, so we use closing
        probability: probResult.probability,
        category: 'safe', // Default bucket, will be sorted out later
        district: dist,
        collegeType: cType,
      ));
    }

    return allRecs;
  }

  Future<RecommendationResult> getRecommendationResult({
    required String category,
    required double cutoff,
    required String preferredCourse,
    String? district,
    List<String> preferredCollegeIds = const [],
    List<String> preferredCollegeNames = const [],
  }) async {
    final all = await getRecommendations(
      category: category,
      cutoff: cutoff,
      interest: preferredCourse,
      district: district,
      preferredCollegeIds: preferredCollegeIds,
      preferredCollegeNames: preferredCollegeNames,
    );
    
    return _enforceRecommendationRules(
      all,
      studentCutoff: cutoff,
      preferredCourse: preferredCourse,
      district: district,
      preferredCollegeNames: preferredCollegeNames,
    );
  }

  RecommendationResult _enforceRecommendationRules(
    List<Recommendation> all, {
    required double studentCutoff,
    required String preferredCourse,
    String? district,
    List<String> preferredCollegeNames = const [],
  }) {
    // Deduplicate
    final deduped = <String, Recommendation>{};
    for (final item in all) {
      final key = '${_normalizeToken(item.collegeName)}|${_normalizeToken(item.courseName)}';
      final existing = deduped[key];
      if (existing == null || item.probability > existing.probability) {
        deduped[key] = item;
      }
    }
    
    final uniqueAll = deduped.values.toList();
    
    final preferredNameTokens = preferredCollegeNames
        .map(_normalizeToken)
        .where((value) => value.isNotEmpty)
        .toList();

    int compareByProbability(Recommendation a, Recommendation b) {
      final byProbability = b.probability.compareTo(a.probability);
      if (byProbability != 0) return byProbability;
      return a.collegeName.toLowerCase().compareTo(b.collegeName.toLowerCase());
    }

    int compareByCollegeTier(Recommendation a, Recommendation b) {
      final byMax = b.maxCutoff.compareTo(a.maxCutoff);
      if (byMax != 0) return byMax;
      final byMin = b.cutoff.compareTo(a.cutoff);
      if (byMin != 0) return byMin;
      return b.probability.compareTo(a.probability);
    }

    bool isUserSelected(Recommendation item) {
      if (preferredNameTokens.isEmpty) return false;
      final collegeToken = _normalizeToken(item.collegeName);
      if (collegeToken.isEmpty) return false;
      
      for (final token in preferredNameTokens) {
        if (token.isEmpty) continue;
        if (collegeToken.contains(token) || token.contains(collegeToken)) return true;
      }
      return false;
    }

    final userSelectedKeys = <String>{
      ...uniqueAll.where(isUserSelected).map((item) =>
          '${_normalizeToken(item.collegeName)}|${_normalizeToken(item.courseName)}'),
    };

    final preferred = uniqueAll.where((item) {
      final key = '${_normalizeToken(item.collegeName)}|${_normalizeToken(item.courseName)}';
      return userSelectedKeys.contains(key);
    }).toList()
      ..sort(compareByProbability);

    final districtToken = district != null ? _normalizeToken(district) : null;

    final safe = uniqueAll.where((item) {
      final key = '${_normalizeToken(item.collegeName)}|${_normalizeToken(item.courseName)}';
      if (userSelectedKeys.contains(key)) return false;
      if (item.probability < 30) return false;
      
      if (districtToken != null && districtToken.isNotEmpty && districtToken != 'any') {
        final itemDistrict = _normalizeToken(item.district ?? '');
        if (itemDistrict.isEmpty) return true;
        return itemDistrict.contains(districtToken) || districtToken.contains(itemDistrict);
      }
      return true;
    }).toList()
      ..sort(compareByCollegeTier);

    return RecommendationResult(
      preferredColleges: preferred,
      safeColleges: safe.take(15).toList(),
    );
  }

  Future<FinalReportResponse> getFinalReport({
    required String studentName,
    required String category,
    required double studentCutoff,
    required String preferredCourse,
    String? district,
    bool hostelRequired = false,
    List<String> preferredCollegeIds = const [],
    List<String> preferredCollegeNames = const [],
  }) async {
    final result = await getRecommendationResult(
      category: category,
      cutoff: studentCutoff,
      preferredCourse: preferredCourse,
      district: district,
      preferredCollegeIds: preferredCollegeIds,
      preferredCollegeNames: preferredCollegeNames,
    );

    List<SafeCollegeResponse> safeResponses = result.safeColleges.map((r) => SafeCollegeResponse(
      collegeName: r.collegeName,
      course: r.courseName,
      collegeCutoff: r.cutoff,
      district: r.district,
      probability: r.probability.toDouble(),
      chanceLabel: r.probability >= 80 ? 'Safe' : (r.probability >= 50 ? 'Moderate' : 'Risky'),
    )).toList();

    return FinalReportResponse(
      studentName: studentName,
      studentCutoff: studentCutoff,
      studentCategory: category,
      preferredCourse: preferredCourse,
      hostelRequired: hostelRequired,
      preferredLocation: district,
      safeColleges: safeResponses,
      targetColleges: [], // Handled by frontend computation
    );
  }

  void warmup() {
    getDistricts();
    getCourses();
    getAllColleges();
  }
}
