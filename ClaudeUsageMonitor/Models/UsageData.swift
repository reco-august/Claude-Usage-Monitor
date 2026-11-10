import Foundation

struct UsageData {
    var planType:        String
    var messagesUsed:    Int        // weekly (seven_day) utilization, 0–100
    var messagesLimit:   Int        // 100 when weekly data present, else 0
    var weeklyResetDate: Date?     // seven_day.resets_at
    var weeklyResetText: String = "" // raw weekday+time string e.g. "Fri 10:00 AM"
    var extraUsageSpent: Double = 0  // € spent on extra usage this billing period
    var extraUsageLimit: Double = 0  // € monthly spend limit for extra usage
    var sonnetPercentage: Double = 0 // seven_day_sonnet utilization (0–1), Max users only
    var sonnetResetDate: Date? = nil // seven_day_sonnet.resets_at
    var claudeDesignPercentage: Double = 0 // seven_day_claude_design utilization (0–1)
    var claudeDesignResetDate: Date? = nil // seven_day_claude_design.resets_at
    var routineRunsUsed:  Int = 0   // daily routine runs used (/v1/code/routines/run-budget)
    var routineRunsLimit: Int = 0   // daily routine runs limit (plan-specific: Pro=5, Max=15, Team/Enterprise=25)
    var rateLimitStatus: String
    var lastUpdated:     Date

    // MARK: - Computed

    var weeklyPercentage: Double {
        guard messagesLimit > 0 else { return 0 }
        return min(1.0, Double(messagesUsed) / Double(messagesLimit))
    }

    var hasExtraUsage: Bool { extraUsageLimit > 0 }

    var hasSonnetData: Bool { sonnetPercentage > 0 }

    var hasClaudeDesignData: Bool { claudeDesignPercentage > 0 }

    var hasRoutineData: Bool { routineRunsLimit > 0 }

    var routineRunsPercentage: Double {
        guard routineRunsLimit > 0 else { return 0 }
        return min(1.0, Double(routineRunsUsed) / Double(routineRunsLimit))
    }

    var routineRunsRemaining: Int { max(0, routineRunsLimit - routineRunsUsed) }

    var sonnetResetLabel: String? {
        guard let date = sonnetResetDate else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return "Resets \(f.string(from: date))"
    }

    var claudeDesignResetLabel: String? {
        guard let date = claudeDesignResetDate else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return "Resets \(f.string(from: date))"
    }

    var extraUsagePercentage: Double {
        guard extraUsageLimit > 0 else { return 0 }
        return min(1.0, extraUsageSpent / extraUsageLimit)
    }

    // MARK: - Reset labels

    var timeUntilReset: String {
        guard let weeklyResetDate else { return "—" }
        let secs = weeklyResetDate.timeIntervalSince(Date())
        guard secs > 0 else { return "Soon" }
        let totalMins = Int(secs / 60)
        let h = totalMins / 60
        let m = totalMins % 60
        let days = h / 24
        if days > 0  { return "\(days)d \(h % 24)h" }
        if h > 0     { return "\(h)h \(m)m" }
        if m > 0     { return "\(m)m" }
        return "< 1m"
    }

    var weeklyResetLabel: String? {
        if !weeklyResetText.isEmpty { return "Resets \(weeklyResetText)" }
        guard let date = weeklyResetDate else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return "Resets \(f.string(from: date))"
    }

    var lastUpdatedFormatted: String {
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: lastUpdated)
    }

    // MARK: - Menu bar label
    var menuBarLabel: String {
        messagesLimit > 0 ? "\(Int(weeklyPercentage * 100))%" : ""
    }

    // MARK: - Stale

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > 600
    }
}
