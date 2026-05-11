import 'package:flutter/foundation.dart';
import 'package:guidex/models/recommendation.dart';
import 'package:guidex/services/api_service.dart';
import 'package:guidex/services/probability_calculator_service.dart';

/// Target College Recommendation Service
///
/// Recommends BEST colleges based on student's profile (NOT user's desires)
///
/// Differences:
/// - PREFERRED: User chooses → System calculates probability
/// - TARGET: System recommends best matches → System calculates probability
///
/// Algorithm:
/// 1. Fetch all colleges from database
/// 2. Filter by: Category, Cutoff range, Location, Course match
/// 3. Score each college (cutoff proximity, location, course match)
/// 4. Calculate probability using strict algorithm
/// 5. Return TOP 15-20 sorted by probability

class TargetCollegeResult {
  final String collegeName;
  final String courseName;
  final double studentCutoff;
  final double collegeCutoff;
  final int probability;
  final String label;
  final String reason;
  final String district;
  final String collegeType;
  final int collegeRank;
  final String category;
  final double matchScore; // 0-100: How well college matches student profile
  final List<String> matchReasons; // Why this college is recommended

  TargetCollegeResult({
    required this.collegeName,
    required this.courseName,
    required this.studentCutoff,
    required this.collegeCutoff,
    required this.probability,
    required this.label,
    required this.reason,
    required this.district,
    required this.collegeType,
    required this.collegeRank,
    required this.category,
    required this.matchScore,
    required this.matchReasons,
  });

  @override
  String toString() {
    return '''
College: $collegeName
Course: $courseName
Location: $district
Type: $collegeType | Rank: $collegeRank

Student Cutoff: $studentCutoff | College Cutoff: $collegeCutoff
Match Score: $matchScore%
Probability: $probability%
Label: $label

Why recommended:
${matchReasons.map((r) => '• $r').join('\n')}

Reason: $reason
''';
  }
}

class TargetCollegeRecommendationService {
  static const int _defaultReturnCount = 15;

  /// Get target college recommendations - Auto-assigned by system
  ///
  /// Algorithm:
  /// 1. Fetch ALL colleges from API
  /// 2. Remove preferred colleges (user-selected)
  /// 3. Calculate probability for each remaining college
  /// 4. Sort by probability descending
  /// 5. Return top colleges
  static Future<List<TargetCollegeResult>> getTargetCollegeRecommendations({
    required double studentCutoff,
    required String category,
    required String courseInterest,
    String? preferredLocation,
    ApiService? apiService,
    int returnCount = _defaultReturnCount,
    List<String> preferredCollegeNames = const [],
  }) async {
    final api = apiService ?? ApiService();

    try {
      debugPrint('🎯 TARGET: Fetching colleges for auto-assign');
      debugPrint('  Cutoff: $studentCutoff, Category: $category');
      debugPrint(
          '  Excluding ${preferredCollegeNames.length} preferred colleges');

      // STEP 1: Get ALL colleges from API
      List<Recommendation> allColleges = [];
      try {
        allColleges = await api.getRecommendations(
          category: category,
          cutoff: studentCutoff,
          interest: courseInterest,
          district: null,
        );
        debugPrint('🎯 ✅ Fetched ${allColleges.length} colleges from API');
      } catch (e) {
        debugPrint('🎯 ❌ API fetch failed: $e');
        return [];
      }

      if (allColleges.isEmpty) {
        debugPrint('🎯 ⚠️ API returned no colleges');
        return [];
      }

      // STEP 2: Remove preferred colleges from consideration
      final List<Recommendation> targetList = [];
      for (final college in allColleges) {
        bool isPreferred = false;
        for (final prefName in preferredCollegeNames) {
          final collegeLower = college.collegeName.toLowerCase().trim();
          final prefLower = prefName.toLowerCase().trim();
          if (collegeLower.contains(prefLower) ||
              prefLower.contains(collegeLower)) {
            isPreferred = true;
            debugPrint('🎯  → Excluding preferred: ${college.collegeName}');
            break;
          }
        }
        if (!isPreferred) {
          targetList.add(college);
        }
      }

      debugPrint(
          '🎯 Remaining candidates: ${targetList.length} (excluded ${preferredCollegeNames.length} preferred)');

      if (targetList.isEmpty) {
        debugPrint('🎯 ❌ No candidates left after filtering');
        return [];
      }

      // STEP 3: Calculate probability for each candidate
      final List<_ScoredCollege> scored = [];

      for (final college in targetList) {
        final isLocationMatch = preferredLocation != null &&
            college.district != null &&
            college.district!.toLowerCase() == preferredLocation.toLowerCase();

        final probResult = ProbabilityCalculatorService.calculateProbability(
          collegeName: college.collegeName,
          courseName: college.courseName,
          studentCutoff: studentCutoff,
          collegeCutoff: college.cutoff > 0 ? college.cutoff : 100.0,
          category: category,
          isPreferredCollege: false,
          isLocationMatch: isLocationMatch,
          hostelAvailable: true,
        );

        scored.add(_ScoredCollege(
          college: college,
          prob: probResult,
          locMatch: isLocationMatch,
        ));
      }

      debugPrint('🎯 Calculated probabilities for ${scored.length} colleges');

      // STEP 4: Sort by probability (descending)
      scored.sort((a, b) => b.prob.probability.compareTo(a.prob.probability));

      // STEP 5: Build results (top N)
      final results = <TargetCollegeResult>[];

      for (final item in scored.take(returnCount)) {
        final reasons = <String>[];

        // Add probability reason
        reasons.add('${item.prob.probability}% match');

        // Add location reason
        if (item.locMatch) {
          reasons.add('In your location');
        }

        results.add(TargetCollegeResult(
          collegeName: item.prob.collegeName,
          courseName: item.prob.courseName,
          studentCutoff: studentCutoff,
          collegeCutoff: item.prob.collegeCutoff,
          probability: item.prob.probability,
          label: item.prob.label,
          reason: item.prob.reason,
          district: item.college.district ?? '',
          collegeType: item.college.collegeType ?? 'Unknown',
          collegeRank: item.college.collegeRank ?? 0,
          category: category,
          matchScore: item.prob.probability.toDouble(),
          matchReasons: reasons,
        ));
      }

      debugPrint('🎯 ✅ Returning ${results.length} target colleges');
      for (int i = 0; i < results.take(5).length; i++) {
        final r = results[i];
        debugPrint(
            '🎯  ${i + 1}. ${r.collegeName}: ${r.probability}% (${r.label})');
      }

      return results;
    } catch (e) {
      debugPrint('🎯 ❌ Exception: $e');
      debugPrint('🎯 Stacktrace: ${StackTrace.current}');
      return [];
    }
  }
}

/// Helper class to store college with calculated probability
class _ScoredCollege {
  final Recommendation college;
  final ProbabilityResult prob;
  final bool locMatch;

  _ScoredCollege({
    required this.college,
    required this.prob,
    required this.locMatch,
  });
}
