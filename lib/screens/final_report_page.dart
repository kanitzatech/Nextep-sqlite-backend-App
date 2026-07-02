import 'package:flutter/material.dart';
import 'package:guidex/models/recommendation.dart';
import 'package:guidex/models/final_report_response.dart';
import 'package:guidex/repository/college_repository.dart';
import 'package:guidex/services/report_export_service.dart';
import 'package:guidex/services/probability_calculator_service.dart';
import 'package:guidex/services/target_college_recommendation_service.dart';

class FinalReportPage extends StatefulWidget {
  final String studentName;
  final String category;
  final double studentCutoff;
  final String preferredCourse;
  final String? district;
  final bool hostelRequired;
  final List<String> preferredCollegeIds;
  final List<String> preferredCollegeNames;
  final List<Recommendation>? allRecommendations;
  final List<Recommendation>? safeColleges;
  final List<Recommendation>? preferredRecommendations;

  const FinalReportPage({
    super.key,
    required this.studentName,
    required this.category,
    required this.studentCutoff,
    required this.preferredCourse,
    this.district,
    required this.hostelRequired,
    required this.preferredCollegeIds,
    required this.preferredCollegeNames,
    this.allRecommendations,
    this.safeColleges,
    this.preferredRecommendations,
  });

  @override
  State<FinalReportPage> createState() => _FinalReportPageState();
}

class _FinalReportPageState extends State<FinalReportPage> {
  final GlobalKey _reportKey = GlobalKey();

  bool _isLoading = true;
  FinalReportResponse? _finalReportResponse;
  List<TargetCollegeResponse> _clientSideTargetColleges = [];
  // Always computed client-side — never depends on backend
  List<SafeCollegeResponse> _clientSidePreferredColleges = [];

  @override
  void initState() {
    super.initState();
    _loadFinalReport();
  }

  List<TargetCollegeResponse> get _allTargets {
    if (_finalReportResponse != null &&
        _finalReportResponse!.targetColleges.isNotEmpty) {
      return _finalReportResponse!.targetColleges;
    }
    return _clientSideTargetColleges;
  }

  /// Preferred colleges shown at the top: always computed client-side with STRICT ALGORITHM.
  /// Client-side computation has improved college name matching (exact → partial → normalized).
  List<SafeCollegeResponse> get _preferredCollegesForDisplay {
    // ALWAYS use client-side computation for preferred colleges
    // It has the improved college name matching logic
    return _clientSidePreferredColleges;
  }

  /// Returns the next 15 target colleges (not overlapping with preferred names)
  List<TargetCollegeResponse> get _targetColleges {
    final preferredNames = widget.preferredCollegeNames
        .map((n) => n.toLowerCase().trim())
        .toList();
    final filtered = _allTargets
        .where((c) => !preferredNames.any((p) =>
            c.collegeName.toLowerCase().trim().contains(p) ||
            p.contains(c.collegeName.toLowerCase().trim())))
        .take(15)
        .toList();

    debugPrint(
        'Target colleges display: ${_allTargets.length} total, ${filtered.length} after removing preferred');

    return filtered;
  }

  Future<void> _loadFinalReport() async {
    try {
      // First, fetch college data to get actual cutoffs for preferred colleges
      final collegeCutoffData = await CollegeRepository().getRecommendationResult(
        category: widget.category,
        cutoff: widget.studentCutoff,
        preferredCourse: widget.preferredCourse,
        district: null,
        preferredCollegeIds: widget.preferredCollegeIds,
        preferredCollegeNames: widget.preferredCollegeNames,
      );

      // Combine all colleges from API
      final allColleges = [
        ...collegeCutoffData.preferredColleges,
        ...collegeCutoffData.safeColleges,
      ];

      // Compute preferred colleges with STRICT ALGORITHM using actual cutoff data
      List<SafeCollegeResponse> clientPreferred =
          _computePreferredCollegesWithAccuracy(allColleges);

      // Load final report from backend
      final response = await CollegeRepository().getFinalReport(
        studentName: widget.studentName,
        category: widget.category,
        studentCutoff: widget.studentCutoff,
        preferredCourse: widget.preferredCourse,
        district: widget.district,
        hostelRequired: widget.hostelRequired,
        preferredCollegeIds: widget.preferredCollegeIds,
        preferredCollegeNames: widget.preferredCollegeNames,
      );

      // If backend returned no target colleges, compute client-side
      List<TargetCollegeResponse> clientTargets = [];
      if (response.targetColleges.isEmpty) {
        debugPrint(
            'Backend returned 0 target colleges → computing client-side...');
        clientTargets = await _computeTargetCollegesClientSide();
        debugPrint(
            'Client-side computed ${clientTargets.length} target colleges.');
      }

      if (mounted) {
        setState(() {
          _finalReportResponse = response;
          _clientSideTargetColleges = clientTargets;
          _clientSidePreferredColleges = clientPreferred;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('API failed, using fallback mode: $e');
      // Fallback: compute using empty college data
      final fallbackPreferred = _computePreferredCollegesClientSide();

      // Try to compute target colleges client-side
      final clientTargets = await _computeTargetCollegesClientSide();
      if (mounted) {
        setState(() {
          _clientSideTargetColleges = clientTargets;
          _clientSidePreferredColleges = fallbackPreferred;
          _isLoading = false;
        });
      }
    }
  }

  /// Computes preferred colleges using STRICT PROBABILITY ALGORITHM
  /// This fetches actual college cutoff data and applies accurate probability calculation
  List<SafeCollegeResponse> _computePreferredCollegesClientSide() {
    if (widget.preferredCollegeNames.isEmpty) return [];

    final result = <SafeCollegeResponse>[];

    // For now, we need to fetch college data to get actual cutoffs
    // This will be called after API loads data
    return result;
  }

  /// NEW METHOD: Compute preferred colleges with STRICT ALGORITHM after API returns data
  List<SafeCollegeResponse> _computePreferredCollegesWithAccuracy(
    List<Recommendation> allCollegesFromApi,
  ) {
    if (widget.preferredCollegeNames.isEmpty) return [];

    final result = <SafeCollegeResponse>[];

    // For each preferred college user selected
    for (final prefName in widget.preferredCollegeNames) {
      if (prefName.trim().isEmpty) continue;

      final prefNameLower = prefName.toLowerCase().trim();

      // IMPROVED MATCHING: Search through ALL colleges from API
      // Try exact match first, then partial matches
      Recommendation? matchedCollege;

      // Step 1: Exact match
      try {
        matchedCollege = allCollegesFromApi.firstWhere((college) =>
            college.collegeName.toLowerCase().trim() == prefNameLower);
      } catch (e) {
        // Not found - try partial match
      }

      // Step 2: Partial match (one contains the other)
      if (matchedCollege == null) {
        try {
          matchedCollege = allCollegesFromApi.firstWhere((college) {
            final collegeLower = college.collegeName.toLowerCase().trim();
            // Try different matching strategies
            return collegeLower.contains(prefNameLower) ||
                prefNameLower.contains(collegeLower) ||
                // Remove common words and try again
                _normalizeCollegeName(collegeLower) ==
                    _normalizeCollegeName(prefNameLower);
          });
        } catch (e) {
          // Not found - will use fallback
        }
      }

      if (matchedCollege != null && matchedCollege.cutoff > 0) {
        // Use STRICT ALGORITHM with actual college cutoff
        final probResult = ProbabilityCalculatorService.calculateProbability(
          collegeName: matchedCollege.collegeName,
          courseName: matchedCollege.courseName,
          studentCutoff: widget.studentCutoff,
          collegeCutoff: matchedCollege.cutoff,
          category: widget.category,
          isPreferredCollege: true, // These are preferred colleges
          isLocationMatch: widget.district != null &&
              matchedCollege.district != null &&
              widget.district!.toLowerCase().trim() ==
                  matchedCollege.district!.toLowerCase().trim(),
          hostelAvailable: widget.hostelRequired,
        );

        result.add(SafeCollegeResponse(
          collegeName: probResult.collegeName,
          course: probResult.courseName,
          collegeCutoff: probResult.collegeCutoff,
          district: widget.district,
          probability: probResult.probability.toDouble(),
          chanceLabel: probResult.label,
          reason: probResult.reason,
          isAvailable: true,
        ));
      } else {
        // Fallback: No college data available or cutoff is 0
        // Try to find ANY college data for this name to get at least the cutoff
        Recommendation? anyMatch;
        try {
          anyMatch = allCollegesFromApi.firstWhere((college) {
            final collegeLower = college.collegeName.toLowerCase().trim();
            return collegeLower.contains(prefNameLower) ||
                prefNameLower.contains(collegeLower);
          });
        } catch (e) {
          // Still not found
        }

        final double fallbackCutoff =
            (anyMatch?.cutoff ?? 0) > 0 ? (anyMatch?.cutoff ?? 0) : 0.0;
        final bool isCourseOffered = anyMatch != null;

        result.add(SafeCollegeResponse(
          collegeName: prefName,
          course: widget.preferredCourse,
          collegeCutoff: fallbackCutoff,
          district: widget.district,
          probability: fallbackCutoff > 0 ? 50.0 : (isCourseOffered ? 50.0 : 0.0), // Conservative default
          chanceLabel: isCourseOffered ? 'Moderate' : 'Not Offered',
          reason: fallbackCutoff > 0
              ? 'College cutoff data found: ${fallbackCutoff.toStringAsFixed(1)}. Estimated probability based on your cutoff ${widget.studentCutoff.toStringAsFixed(1)}.'
              : (isCourseOffered
                  ? 'Unable to fetch college cutoff data. Estimated probability based on your cutoff ${widget.studentCutoff.toStringAsFixed(1)}.'
                  : 'This college does not offer ${widget.preferredCourse}.'),
          isAvailable: isCourseOffered,
        ));
      }
    }

    return result;
  }

  /// Normalize college name by removing common words for better matching
  String _normalizeCollegeName(String name) {
    return name
        .replaceAll(
            RegExp(r'\b(college|engineering|institute|iit|nit|university)\b',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _downloadAsPDF() async {
    await ReportExportService.exportToPDF(
      studentName: widget.studentName,
      category: widget.category,
      studentCutoff: widget.studentCutoff,
      preferredCourse: widget.preferredCourse,
      safeColleges: [],
      targetColleges: _targetColleges,
      preferredColleges: _preferredCollegesForDisplay,
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // CLIENT-SIDE TARGET COLLEGE ALGORITHM
  // Exact formula as specified:
  //   finalScore = 0.4×cutoff + 0.2×location + 0.15×interest
  //              + 0.1×hostel + 0.1×category + 0.05×preference
  //   Filter: finalScore >= 0.55  (NO upper cap)
  //   Sort by finalScore DESC, take top 15
  // ════════════════════════════════════════════════════════════════════════
  Future<List<TargetCollegeResponse>> _computeTargetCollegesClientSide() async {
    try {
      debugPrint(
          'Computing target colleges: cutoff=${widget.studentCutoff}, category=${widget.category}, course=${widget.preferredCourse}, location=${widget.district}');

      // Use the new TargetCollegeRecommendationService to get recommendations
      // PASS preferred college names so they are EXCLUDED from target colleges
      final recommendations = await TargetCollegeRecommendationService
          .getTargetCollegeRecommendations(
        studentCutoff: widget.studentCutoff,
        category: widget.category,
        courseInterest: widget.preferredCourse,
        preferredLocation: widget.district,
        returnCount: 15,
        preferredCollegeNames: widget.preferredCollegeNames, // ← EXCLUDE these
      );

      debugPrint(
          'Target colleges computed: ${recommendations.length} recommendations');
      for (final rec in recommendations.take(5)) {
        debugPrint(
            'Target: ${rec.collegeName} - ${rec.probability}% (${rec.label})');
      }

      // Convert TargetCollegeResult to TargetCollegeResponse for display
      return recommendations
          .map((rec) => TargetCollegeResponse(
                collegeName: rec.collegeName,
                course: rec.courseName,
                scorePercentage: rec.probability.toDouble(),
                district: rec.district,
                chanceLabel: rec.label,
                cutoffScore: 0.0,
                locationScore: 0.0,
                interestScore: 0.0,
                hostelScore: 0.0,
                categoryScore: 0.0,
                preferenceBonus: 0.0,
                cutoff: rec.collegeCutoff,
                probability: rec.probability.toDouble(),
                reason: rec.reason,
                matchScore: rec.matchScore,
                matchReasons: rec.matchReasons,
              ))
          .toList();
    } catch (e) {
      debugPrint('Target college recommendation failed: $e');
      debugPrint('Error stacktrace: ${StackTrace.current}');
      return [];
    }
  }

  /// Returns true if two course strings are related (e.g. CSE ↔ Computer Science)
  bool _courseRelated(String pref, String actual) {
    const aliases = <String, List<String>>{
      'computer science engineering': ['cse', 'computer science', 'cs'],
      'information technology': ['it'],
      'electronics and communication': ['ece', 'ec'],
      'electrical and electronics': ['eee', 'ee'],
      'mechanical engineering': ['me', 'mech'],
      'artificial intelligence and data science': ['ai', 'aids', 'ad', 'ai ds'],
      'civil engineering': ['ce', 'civil'],
      'biomedical engineering': ['bme', 'bio'],
      'biotechnology': ['bt', 'bio'],
    };
    for (final entry in aliases.entries) {
      final variants = [entry.key, ...entry.value];
      final prefMatches =
          variants.any((v) => pref.contains(v) || v.contains(pref));
      final actualMatches =
          variants.any((v) => actual.contains(v) || v.contains(actual));
      if (prefMatches && actualMatches) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Final Report'),
        elevation: 0,
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: RepaintBoundary(
                key: _reportKey,
                child: Container(
                  color: Colors.grey.shade50, // Background for screenshot
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Student Profile Header
                      _buildStudentHeader(),
                      const SizedBox(height: 24),

                      // Target Colleges Section (contains both Preferred Choices + Target Colleges)
                      _buildTargetCollegesSection(),
                      const SizedBox(height: 24),

                      // Download Section
                      // (Moved into Target Colleges Section)
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildStudentHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student Profile',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.studentName,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildProfileInfo(
                  icon: Icons.trending_up,
                  label: 'Cutoff',
                  value: widget.studentCutoff.toStringAsFixed(2),
                ),
              ),
              Expanded(
                child: _buildProfileInfo(
                  icon: Icons.school,
                  label: 'Category',
                  value: widget.category.toUpperCase(),
                ),
              ),
              Expanded(
                child: _buildProfileInfo(
                  icon: Icons.code,
                  label: 'Course',
                  value: _getShortCourseName(widget.preferredCourse),
                ),
              ),
            ],
          ),
          if (widget.district != null && widget.district!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'District: ${widget.district}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.white.withValues(alpha: 0.8),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTargetCollegesSection() {
    final colleges = _targetColleges;
    final preferredColleges = _preferredCollegesForDisplay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Preferred Choices (student's own picks) ──────────────────────
        if (preferredColleges.isNotEmpty) ...[
          _buildCategoryHeader(
            'Your Preferred Colleges',
            'Admission probability for your selected colleges',
            Colors.indigo.shade600,
          ),
          const SizedBox(height: 12),
          ...preferredColleges.asMap().entries.map((entry) =>
              _buildPreferredCollegeCard(entry.value, entry.key + 1)),
          const SizedBox(height: 24),
        ] else if (widget.preferredCollegeNames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: _buildEmptyState(
                'Your selected colleges could not be loaded. Please try again.'),
          ),
        // ─────────────────────────────────────────────────────────────────

        // Target Colleges Header (orange)
        _buildCategoryHeader('Target Colleges', 'Best recommended alternatives',
            Colors.orange.shade600),
        const SizedBox(height: 16),

        if (colleges.isEmpty)
          _buildEmptyState('No additional target colleges found.')
        else
          Column(
            children: colleges.asMap().entries.map((entry) {
              final index = entry.key;
              final college = entry.value;
              return _buildTargetCollegeCard(college, index + 1,
                  isPreferred: false);
            }).toList(),
          ),
        const SizedBox(height: 32),
        Center(
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _downloadAsPDF,
              icon: const Icon(Icons.download, size: 20),
              label: const Text(
                'Download Analysis Report (PDF)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildCategoryHeader(String title, String subtitle, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildTargetCollegeCard(TargetCollegeResponse college, int rank,
      {bool isPreferred = false}) {
    // Accent color: green for preferred, orange for target
    final Color accentColor =
        isPreferred ? Colors.green.shade600 : Colors.orange.shade600;
    final Color accentLight =
        isPreferred ? Colors.green.shade50 : Colors.orange.shade50;
    final Color accentDark =
        isPreferred ? Colors.green.shade700 : Colors.orange.shade700;
    final Color borderColor =
        isPreferred ? Colors.green.shade200 : Colors.orange.shade200;

    // Chance label color still reflects actual probability
    Color statusColor;
    if (college.chanceLabel == 'Excellent' || college.chanceLabel == 'Strong') {
      statusColor = Colors.green.shade600;
    } else if (college.chanceLabel == 'Good' ||
        college.chanceLabel == 'Moderate') {
      statusColor = Colors.orange.shade600;
    } else if (college.chanceLabel == 'Competitive') {
      statusColor = Colors.blue.shade600;
    } else {
      statusColor = Colors.red.shade600;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: isPreferred ? borderColor : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rank Badge
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: accentDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // College Header
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      college.collegeName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      college.course,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Status Label
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  college.chanceLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildScoreMetric('Probability', '${college.scorePercentage}%',
                  Icons.analytics),
              _buildScoreMetric(
                  'Min Cutoff', '${college.cutoff}', Icons.trending_down),
              _buildScoreMetric(
                  'Location',
                  '${(college.locationScore * 100).toInt()}%',
                  Icons.location_on),
            ],
          ),
        ],
      ),
    );
  }

  /// Card for SafeCollegeResponse (Real backend data for Preferred Choices)
  Widget _buildPreferredCollegeCard(SafeCollegeResponse college, int rank) {
    final bool isAvailable = college.isAvailable;
    final double prob = college.probability;

    final statusColor = !isAvailable
        ? Colors.grey.shade600
        : (prob >= 75
            ? Colors.green.shade600
            : (prob >= 60 ? Colors.orange.shade600 : Colors.red.shade600));

    final cardBorderColor =
        !isAvailable ? Colors.grey.shade300 : Colors.green.shade200;
    final badgeColor =
        !isAvailable ? Colors.grey.shade100 : Colors.green.shade50;
    final badgeTextColor =
        !isAvailable ? Colors.grey.shade700 : Colors.green.shade700;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: (isAvailable ? Colors.green : Colors.grey)
                .withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rank Badge
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: badgeTextColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // College Header
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      college.collegeName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      college.course,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Status Label
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  college.chanceLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (isAvailable) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildScoreMetric('Probability', '${prob.toStringAsFixed(0)}%',
                    Icons.analytics),
                _buildScoreMetric('Your Cutoff',
                    widget.studentCutoff.toStringAsFixed(1), Icons.person),
                _buildScoreMetric(
                    'Min Cutoff',
                    college.collegeCutoff.toStringAsFixed(1),
                    Icons.trending_down),
              ],
            ),
          ],
          if (college.reason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.1)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                      !isAvailable
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 14,
                      color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      college.reason,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreMetric(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  String _getShortCourseName(String course) {
    const courseMap = {
      'Computer Science Engineering': 'CSE',
      'Information Technology': 'IT',
      'Electronics and Communication Engineering': 'ECE',
      'Electrical and Electronics Engineering': 'EEE',
      'Mechanical Engineering': 'ME',
      'Civil Engineering': 'CE',
      'Artificial Intelligence and Data Science': 'AI&DS',
      'Biomedical Engineering': 'BME',
      'Chemical Engineering': 'ChE',
      'Biotechnology': 'BT',
    };
    return courseMap[course] ?? course.substring(0, 3).toUpperCase();
  }
}

// ── Private helper for sorting during client-side computation ──────────────
class _ScoredCollege {
  final double finalScore;
  final TargetCollegeResponse response;
  const _ScoredCollege({required this.finalScore, required this.response});
}
