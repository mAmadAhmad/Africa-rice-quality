class RiceLogic {
  static Map<String, dynamic> interpretResults(Map<String, dynamic> rawData) {
    // Counts
    final double total = rawData['Total_Count'] ?? 0.0;
    final double broken = rawData['Broken_Count'] ?? 0.0;
    final double long = rawData['Long_Count'] ?? 0.0;
    final double medium = rawData['Medium_Count'] ?? 0.0;
    final double black = rawData['Black_Count'] ?? 0.0;
    final double chalky = rawData['Chalky_Count'] ?? 0.0;
    final double red = rawData['Red_Count'] ?? 0.0;
    final double yellow = rawData['Yellow_Count'] ?? 0.0;
    final double green = rawData['Green_Count'] ?? 0.0;
    
    // Measures (Now securely coming from the isolate)
    final double avgLength = rawData['Avg_Length'] ?? 0.0; 
    final double avgWidth = rawData['Avg_Width'] ?? 0.0;
    final double lwr = rawData['LWR'] ?? 0.0; 
    final double lStar = rawData['Avg_L'] ?? 0.0; 
    final double aStar = rawData['Avg_A'] ?? 0.0; 
    final double bStar = rawData['Avg_B'] ?? 0.0; 

    final safeTotal = total > 0 ? total : 1.0;

    // Percentages
    final double brokenPct = (broken / safeTotal) * 100;
    final double longPct = (long / safeTotal) * 100;
    final double mediumPct = (medium / safeTotal) * 100;
    final double short = (total - broken - long - medium).clamp(0, total);
    final double shortPct = (short / safeTotal) * 100;

    final double blackPct = (black / safeTotal) * 100;
    final double chalkyPct = (chalky / safeTotal) * 100;
    final double redPct = (red / safeTotal) * 100;
    final double yellowPct = (yellow / safeTotal) * 100;
    final double greenPct = (green / safeTotal) * 100;

    // Grades & Classifications
    String grade = "Below Grade 3 (>20% Broken)";
    if (brokenPct < 5.0) grade = "Premium";
    else if (brokenPct <= 10.0) grade = "Grade 1";
    else if (brokenPct <= 15.0) grade = "Grade 2";
    else if (brokenPct <= 20.0) grade = "Grade 3";

    String shape = "Unknown";
    if (lwr < 2.2) shape = "Bold";
    else if (lwr <= 2.9) shape = "Medium";
    else shape = "Slender";

    String lengthClass = "Mixed";
    if (longPct > 90.0) lengthClass = "Long";
    else if (mediumPct > 90.0) lengthClass = "Medium";
    else if (shortPct > 90.0) lengthClass = "Short";

    String chalkinessStatus = chalkyPct >= 20.0 ? "Chalky" : "Not Chalky";

    return {
      // Core Classifications (For Simple View)
      'milling_grade': grade,
      'grain_shape': shape,
      'length_class': lengthClass,
      'chalkiness': chalkinessStatus,
      
      // Flags
      'flag_damaged': blackPct > 10.0,
      'flag_immature': greenPct > 10.0,
      'flag_red_strips': redPct > 10.0,
      'flag_fermented': yellowPct > 10.0,
      
      // Percentages
      'broken_pct': brokenPct.toStringAsFixed(1),
      'black_pct': blackPct.toStringAsFixed(1),
      'chalky_pct': chalkyPct.toStringAsFixed(1),
      'red_pct': redPct.toStringAsFixed(1),
      'yellow_pct': yellowPct.toStringAsFixed(1),
      'green_pct': greenPct.toStringAsFixed(1),

      // Raw Counts for the Checklist
      'total_count': total.toInt(),
      'broken_count': broken.toInt(),
      'long_count': long.toInt(),
      'medium_count': medium.toInt(),
      
      // Physical Measurements
      'avg_length': avgLength.toStringAsFixed(2),
      'avg_width': avgWidth.toStringAsFixed(2),
      'lwr': lwr.toStringAsFixed(2), 
      
      // CIELAB Color Profile
      'cielab_l': lStar.toStringAsFixed(2),
      'cielab_a': aStar.toStringAsFixed(2),
      'cielab_b': bStar.toStringAsFixed(2),
    };
  }
}