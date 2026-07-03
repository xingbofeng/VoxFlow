import Foundation

extension BuiltinAgentToolHost {
    func notebookEdit(_ call: BuiltinAgentToolCall) -> BuiltinAgentToolResult {
        guard let path = requiredString("notebook_path", in: call) else {
            return .failure(toolName: call.name, code: "missing_notebook_path")
        }
        guard let newSource = call.arguments["new_source"]?.stringValue else {
            return .failure(toolName: call.name, code: "missing_new_source")
        }
        let editMode = call.arguments["edit_mode"]?.stringValue ?? "replace"
        guard ["replace", "insert", "delete"].contains(editMode) else {
            return .failure(toolName: call.name, code: "invalid_edit_mode")
        }
        let url = resolvedFileURL(path: path)
        guard url.pathExtension == "ipynb" else {
            return .failure(toolName: call.name, code: "not_notebook")
        }
        if let failure = fileAccessFailure(toolName: call.name, path: path, url: url, requireWorkspaceForRelativePath: true) {
            return failure
        }
        guard let readState = readFileState[url.path] else {
            return .failure(toolName: call.name, code: "file_not_read")
        }
        guard readState.isFullRead else {
            return .failure(toolName: call.name, code: "file_not_fully_read")
        }
        guard fileModificationTime(url) <= readState.modifiedAt else {
            return .failure(toolName: call.name, code: "file_modified_since_read")
        }

        do {
            let originalFile = try String(contentsOf: url, encoding: .utf8)
            var notebook = try notebookObject(from: originalFile)
            var cells = try notebookCells(from: notebook)
            let language = notebookLanguage(from: notebook)
            let cellID = call.arguments["cell_id"]?.stringValue
            let resolvedIndex = try resolveNotebookCellIndex(
                cellID: cellID,
                editMode: editMode,
                cells: cells
            )

            var outputCellID = cellID
            let outputCellType: String
            if editMode == "delete" {
                outputCellType = cells[resolvedIndex]["cell_type"] as? String ?? "code"
                cells.remove(at: resolvedIndex)
            } else if editMode == "insert" {
                guard let cellType = call.arguments["cell_type"]?.stringValue,
                      ["code", "markdown"].contains(cellType) else {
                    return .failure(toolName: call.name, code: "missing_cell_type")
                }
                let generatedID = shouldWriteNotebookCellIDs(notebook)
                    ? String(UUID().uuidString.lowercased().prefix(12))
                    : nil
                var newCell: [String: Any] = [
                    "cell_type": cellType,
                    "metadata": [:],
                    "source": newSource
                ]
                if let generatedID {
                    newCell["id"] = generatedID
                    outputCellID = generatedID
                }
                if cellType == "code" {
                    newCell["execution_count"] = NSNull()
                    newCell["outputs"] = []
                }
                cells.insert(newCell, at: resolvedIndex)
                outputCellType = cellType
            } else {
                var targetCell = cells[resolvedIndex]
                let requestedCellType = call.arguments["cell_type"]?.stringValue
                if let requestedCellType, !["code", "markdown"].contains(requestedCellType) {
                    return .failure(toolName: call.name, code: "invalid_cell_type")
                }
                targetCell["source"] = newSource
                if (targetCell["cell_type"] as? String) == "code" {
                    targetCell["execution_count"] = NSNull()
                    targetCell["outputs"] = []
                }
                if let requestedCellType {
                    targetCell["cell_type"] = requestedCellType
                }
                cells[resolvedIndex] = targetCell
                outputCellType = targetCell["cell_type"] as? String ?? "code"
            }

            notebook["cells"] = cells
            let updatedFile = try serializedNotebook(notebook)
            try updatedFile.write(to: url, atomically: true, encoding: .utf8)
            readFileState[url.path] = BuiltinAgentReadFileState(
                content: updatedFile,
                modifiedAt: fileModificationTime(url),
                isFullRead: true
            )

            var result: [String: BuiltinAgentJSONValue] = [
                "new_source": .string(newSource),
                "cell_type": .string(outputCellType),
                "language": .string(language),
                "edit_mode": .string(editMode),
                "notebook_path": .string(url.path),
                "original_file": .string(originalFile),
                "updated_file": .string(updatedFile)
            ]
            if let outputCellID {
                result["cell_id"] = .string(outputCellID)
            }
            return .success(toolName: call.name, result: result)
        } catch let error as BuiltinAgentNotebookEditError {
            return .failure(toolName: call.name, code: error.code, message: error.message)
        } catch {
            return .failure(toolName: call.name, code: "notebook_edit_failed", message: error.localizedDescription)
        }
    }

    private func notebookObject(from source: String) throws -> [String: Any] {
        guard let data = source.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BuiltinAgentNotebookEditError(code: "invalid_notebook_json", message: "Notebook is not valid JSON.")
        }
        return object
    }

    private func notebookCells(from notebook: [String: Any]) throws -> [[String: Any]] {
        guard let cells = notebook["cells"] as? [[String: Any]] else {
            throw BuiltinAgentNotebookEditError(code: "missing_cells", message: "Notebook does not contain a cells array.")
        }
        return cells
    }

    private func notebookLanguage(from notebook: [String: Any]) -> String {
        let metadata = notebook["metadata"] as? [String: Any]
        let languageInfo = metadata?["language_info"] as? [String: Any]
        return languageInfo?["name"] as? String ?? "python"
    }

    private func resolveNotebookCellIndex(
        cellID: String?,
        editMode: String,
        cells: [[String: Any]]
    ) throws -> Int {
        guard let cellID, !cellID.isEmpty else {
            if editMode == "insert" {
                return 0
            }
            throw BuiltinAgentNotebookEditError(code: "missing_cell_id", message: "Cell ID must be specified when not inserting a new cell.")
        }
        let baseIndex = try baseNotebookCellIndex(cellID: cellID, cells: cells)
        return editMode == "insert" ? baseIndex + 1 : baseIndex
    }

    private func baseNotebookCellIndex(cellID: String, cells: [[String: Any]]) throws -> Int {
        if let index = cells.firstIndex(where: { $0["id"] as? String == cellID }) {
            return index
        }
        if let parsedIndex = parseNotebookCellIndexAlias(cellID) {
            guard cells.indices.contains(parsedIndex) else {
                throw BuiltinAgentNotebookEditError(code: "cell_not_found", message: "Cell with index \(parsedIndex) does not exist in notebook.")
            }
            return parsedIndex
        }
        throw BuiltinAgentNotebookEditError(code: "cell_not_found", message: "Cell with ID \"\(cellID)\" not found in notebook.")
    }

    private func parseNotebookCellIndexAlias(_ cellID: String) -> Int? {
        guard cellID.hasPrefix("cell-") else { return nil }
        return Int(cellID.dropFirst("cell-".count))
    }

    private func shouldWriteNotebookCellIDs(_ notebook: [String: Any]) -> Bool {
        let nbformat = notebook["nbformat"] as? Int ?? 4
        let minor = notebook["nbformat_minor"] as? Int ?? 0
        return nbformat > 4 || (nbformat == 4 && minor >= 5)
    }

    private func serializedNotebook(_ notebook: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: notebook, options: [.prettyPrinted])
        guard let text = String(data: data, encoding: .utf8) else {
            throw BuiltinAgentNotebookEditError(code: "serialization_failed", message: "Notebook JSON could not be serialized.")
        }
        return text
    }
}

private struct BuiltinAgentNotebookEditError: Error {
    let code: String
    let message: String
}
