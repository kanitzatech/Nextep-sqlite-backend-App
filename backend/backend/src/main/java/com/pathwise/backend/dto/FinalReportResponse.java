package com.pathwise.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.List;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FinalReportResponse {
    
    // Student Info
    private String studentName;
    private Double studentCutoff;
    private String studentCategory;
    private String preferredCourse;
    private String preferredLocation;
    private Boolean hostelRequired;
    private List<String> preferredCollegeIds;
    
    // Safe Colleges (10) - based on cutoff + margin
    private List<SafeCollegeResponse> safeColleges;
    
    // Target Colleges (10) - based on weighted scoring
    private List<TargetCollegeResponse> targetColleges;
    
    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class SafeCollegeResponse {
        private String collegeName;
        private String course;
        private Double collegeCutoff;
        private String chanceLabel;  // "High (80-95%)"
        private Double probability;
        private String district;
        private String reason;
        private Boolean isAvailable;
    }
    
    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class TargetCollegeResponse {
        private String collegeName;
        private String course;
        private Double scorePercentage;
        private String chanceLabel;  // "Strong Chance", "Moderate", "Dream"
        private String district;
        private Double cutoff;
        
        // Score breakdown
        private Double cutoffScore;
        private Double locationScore;
        private Double interestScore;
        private Double hostelScore;
        private Double categoryScore;
        private Double preferenceBonus;
    }

    // Nested classes for analysis
    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class PreferredCollegeAnalysis {
        private String college_name;
        private String course;
        private Double your_cutoff;
        private Double college_cutoff;
        private Double probability;
        private String chance_label;
        private String reason;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @Builder
    public static class TargetCollege {
        private String college_name;
        private String course;
        private Double score;
        private String chance_label;
    }
}
