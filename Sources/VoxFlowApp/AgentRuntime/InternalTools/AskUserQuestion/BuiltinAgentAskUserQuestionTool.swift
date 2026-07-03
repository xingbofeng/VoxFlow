import Foundation

private struct BuiltinAgentQuestionOption: Equatable, Sendable {
    let label: String
    let description: String
    let preview: String?

    var json: BuiltinAgentJSONValue {
        var object: [String: BuiltinAgentJSONValue] = [
            "label": .string(label),
            "description": .string(description)
        ]
        if let preview {
            object["preview"] = .string(preview)
        }
        return .object(object)
    }
}

private struct BuiltinAgentQuestion: Equatable, Sendable {
    let question: String
    let header: String
    let options: [BuiltinAgentQuestionOption]
    let multiSelect: Bool

    var json: BuiltinAgentJSONValue {
        .object([
            "question": .string(question),
            "header": .string(header),
            "options": .array(options.map(\.json)),
            "multiSelect": .bool(multiSelect)
        ])
    }
}

extension BuiltinAgentToolHost {
    func askUserQuestion(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard case let .array(rawQuestions)? = call.arguments["questions"] else {
            return .failure(toolName: call.name, code: "missing_questions")
        }
        guard (1...4).contains(rawQuestions.count) else {
            return .failure(toolName: call.name, code: "invalid_question_count")
        }

        do {
            let questions = try rawQuestions.map(parseQuestion)
            try validateQuestionUniqueness(questions)
            for question in questions {
                await environment.executor.notifyUser(question.question)
            }

            let answers = stringRecord("answers", in: call)
            var result: [String: BuiltinAgentJSONValue] = [
                "kind": .string("questions_answered"),
                "questions": .array(questions.map(\.json)),
                "answers": .object(answers.mapValues(BuiltinAgentJSONValue.string))
            ]
            if let annotations = call.arguments["annotations"] {
                result["annotations"] = annotations
            }
            return .success(toolName: call.name, result: result)
        } catch let error as BuiltinAgentToolHostError {
            return .failure(toolName: call.name, code: error.code, message: error.message)
        } catch {
            return .failure(toolName: call.name, code: "invalid_questions", message: error.localizedDescription)
        }
    }

    private func parseQuestion(_ value: BuiltinAgentJSONValue) throws -> BuiltinAgentQuestion {
        guard case let .object(object) = value else {
            throw BuiltinAgentToolHostError(code: "invalid_question", message: "Question must be an object.")
        }
        guard let question = nonEmpty(object["question"]?.stringValue) else {
            throw BuiltinAgentToolHostError(code: "missing_question_text", message: "Question text is required.")
        }
        guard let header = nonEmpty(object["header"]?.stringValue) else {
            throw BuiltinAgentToolHostError(code: "missing_question_header", message: "Question header is required.")
        }
        guard header.count <= 12 else {
            throw BuiltinAgentToolHostError(code: "question_header_too_long", message: "Question header must be at most 12 characters.")
        }
        guard case let .array(rawOptions)? = object["options"] else {
            throw BuiltinAgentToolHostError(code: "missing_question_options", message: "Question options are required.")
        }
        guard (1...4).contains(rawOptions.count) else {
            throw BuiltinAgentToolHostError(code: "invalid_option_count", message: "Question must have 1-4 options.")
        }
        let options = try rawOptions.map(parseQuestionOption)
        let labels = options.map(\.label)
        guard labels.count == Set(labels).count else {
            throw BuiltinAgentToolHostError(code: "duplicate_option_label", message: "Option labels must be unique within a question.")
        }
        let multiSelect: Bool
        if case let .bool(value)? = object["multiSelect"] {
            multiSelect = value
        } else {
            multiSelect = false
        }
        return BuiltinAgentQuestion(
            question: question,
            header: header,
            options: options,
            multiSelect: multiSelect
        )
    }

    private func parseQuestionOption(_ value: BuiltinAgentJSONValue) throws -> BuiltinAgentQuestionOption {
        guard case let .object(object) = value else {
            throw BuiltinAgentToolHostError(code: "invalid_option", message: "Question option must be an object.")
        }
        guard let label = nonEmpty(object["label"]?.stringValue) else {
            throw BuiltinAgentToolHostError(code: "missing_option_label", message: "Option label is required.")
        }
        guard let description = nonEmpty(object["description"]?.stringValue) else {
            throw BuiltinAgentToolHostError(code: "missing_option_description", message: "Option description is required.")
        }
        return BuiltinAgentQuestionOption(
            label: label,
            description: description,
            preview: object["preview"]?.stringValue
        )
    }

    private func validateQuestionUniqueness(_ questions: [BuiltinAgentQuestion]) throws {
        let texts = questions.map(\.question)
        guard texts.count == Set(texts).count else {
            throw BuiltinAgentToolHostError(code: "duplicate_question", message: "Question texts must be unique.")
        }
    }

    private func stringRecord(_ key: String, in call: BuiltinAgentToolCall) -> [String: String] {
        guard case let .object(object)? = call.arguments[key] else {
            return [:]
        }
        return object.reduce(into: [:]) { partialResult, element in
            if let value = element.value.stringValue {
                partialResult[element.key] = value
            }
        }
    }
}
