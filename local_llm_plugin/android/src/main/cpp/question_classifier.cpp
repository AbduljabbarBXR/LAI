#pragma once
#include <string>
#include <algorithm>
#include <cctype>

// Question classification enum for Smart Limits
enum QuestionType {
    QUICK_FACT = 0,      // 200 tokens (2-3 seconds)
    EXPLANATION = 1,     // 200 tokens (4-5 seconds) 
    ANALYSIS = 2,        // 256 tokens (5-6 seconds)
    CREATIVE = 3,        // 300 tokens (5-6 seconds)
    TECHNICAL = 4,       // 350 tokens (5-6 seconds)
    DEFAULT = 5          // 180 tokens (3-4 seconds)
};

/**
 * Classify question type based on content analysis
 * Returns the most appropriate QuestionType for the given question
 */
QuestionType classifyQuestion(const std::string& question) {
    if (question.empty()) {
        return DEFAULT;
    }
    
    // Convert to lowercase for case-insensitive matching
    std::string lowerQuestion = question;
    std::transform(lowerQuestion.begin(), lowerQuestion.end(), 
                   lowerQuestion.begin(), ::tolower);
    
    // Quick Facts: Short questions asking for definitions or basic info
    if ((lowerQuestion.find("what is") != std::string::npos) ||
        (lowerQuestion.find("who is") != std::string::npos) ||
        (lowerQuestion.find("define") != std::string::npos) ||
        (lowerQuestion.find("what are") != std::string::npos) ||
        (lowerQuestion.find("when is") != std::string::npos) ||
        (lowerQuestion.find("where is") != std::string::npos) ||
        (lowerQuestion.find("which is") != std::string::npos)) {
        return QUICK_FACT;
    }
    
    // Quick questions with question mark and short length
    if ((lowerQuestion.find('?') != std::string::npos) && 
        (lowerQuestion.length() < 50)) {
        return QUICK_FACT;
    }
    
    // Explanations: Questions asking for detailed understanding
    if ((lowerQuestion.find("explain") != std::string::npos) ||
        (lowerQuestion.find("how does") != std::string::npos) ||
        (lowerQuestion.find("why does") != std::string::npos) ||
        (lowerQuestion.find("how do") != std::string::npos) ||
        (lowerQuestion.find("why do") != std::string::npos) ||
        (lowerQuestion.find("describe") != std::string::npos) ||
        (lowerQuestion.find("tell me about") != std::string::npos) ||
        (lowerQuestion.find("what happens") != std::string::npos) ||
        (lowerQuestion.find("how does") != std::string::npos)) {
        return EXPLANATION;
    }
    
    // Analysis: Questions requiring detailed analysis and comparison
    if ((lowerQuestion.find("analyze") != std::string::npos) ||
        (lowerQuestion.find("compare") != std::string::npos) ||
        (lowerQuestion.find("pros and cons") != std::string::npos) ||
        (lowerQuestion.find("advantages") != std::string::npos) ||
        (lowerQuestion.find("disadvantages") != std::string::npos) ||
        (lowerQuestion.find("benefits") != std::string::npos) ||
        (lowerQuestion.find("drawbacks") != std::string::npos) ||
        (lowerQuestion.find("difference between") != std::string::npos) ||
        (lowerQuestion.find("versus") != std::string::npos) ||
        (lowerQuestion.find("vs ") != std::string::npos) ||
        (lowerQuestion.find("vs.") != std::string::npos)) {
        return ANALYSIS;
    }
    
    // Creative: Questions asking for creative content
    if ((lowerQuestion.find("write") != std::string::npos) ||
        (lowerQuestion.find("create") != std::string::npos) ||
        (lowerQuestion.find("story") != std::string::npos) ||
        (lowerQuestion.find("poem") != std::string::npos) ||
        (lowerQuestion.find("poetry") != std::string::npos) ||
        (lowerQuestion.find("essay") != std::string::npos) ||
        (lowerQuestion.find("article") != std::string::npos) ||
        (lowerQuestion.find("design") != std::string::npos) ||
        (lowerQuestion.find("compose") != std::string::npos) ||
        (lowerQuestion.find("generate") != std::string::npos) ||
        (lowerQuestion.find("make up") != std::string::npos)) {
        return CREATIVE;
    }
    
    // Technical: Questions about coding and technical implementation
    if ((lowerQuestion.find("code") != std::string::npos) ||
        (lowerQuestion.find("program") != std::string::npos) ||
        (lowerQuestion.find("implement") != std::string::npos) ||
        (lowerQuestion.find("algorithm") != std::string::npos) ||
        (lowerQuestion.find("function") != std::string::npos) ||
        (lowerQuestion.find("method") != std::string::npos) ||
        (lowerQuestion.find("syntax") != std::string::npos) ||
        (lowerQuestion.find("debug") != std::string::npos) ||
        (lowerQuestion.find("compile") != std::string::npos) ||
        (lowerQuestion.find("execute") != std::string::npos) ||
        (lowerQuestion.find("api") != std::string::npos) ||
        (lowerQuestion.find("framework") != std::string::npos)) {
        return TECHNICAL;
    }
    
    // Check for question length and complexity for better categorization
    size_t wordCount = 0;
    size_t lastPos = 0;
    while (lastPos < lowerQuestion.length()) {
        size_t pos = lowerQuestion.find(' ', lastPos);
        if (pos == std::string::npos) pos = lowerQuestion.length();
        if (pos > lastPos) wordCount++;
        lastPos = pos + 1;
    }
    
    // Long questions that are not obviously creative or technical
    if (wordCount > 15) {
        return ANALYSIS; // Assume complex analysis for longer questions
    }
    
    // Default to explanation for typical questions
    return DEFAULT;
}

/**
 * Get the appropriate token limit for a given QuestionType
 * Returns the number of tokens that should be generated for this question type
 */
int getTokenLimitForQuestionType(QuestionType type) {
    switch (type) {
        case QUICK_FACT: 
            return 200;   // Enhanced quick answer - 2-3 seconds
        case EXPLANATION: 
            return 200;   // Balanced explanation - 4-5 seconds
        case ANALYSIS: 
            return 256;   // Detailed response - 5-6 seconds
        case CREATIVE: 
            return 300;   // Creative content - 5-6 seconds
        case TECHNICAL: 
            return 350;   // Technical details - 5-6 seconds
        case DEFAULT:
        default:
            return 180;   // Default reasonable length - 3-4 seconds
    }
}

/**
 * Get a string representation of the QuestionType for logging
 */
const char* getQuestionTypeName(QuestionType type) {
    switch (type) {
        case QUICK_FACT: return "QUICK_FACT";
        case EXPLANATION: return "EXPLANATION";
        case ANALYSIS: return "ANALYSIS";
        case CREATIVE: return "CREATIVE";
        case TECHNICAL: return "TECHNICAL";
        case DEFAULT: return "DEFAULT";
        default: return "UNKNOWN";
    }
}