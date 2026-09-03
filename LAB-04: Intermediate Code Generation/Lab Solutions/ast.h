#ifndef AST_H
#define AST_H

#include <iostream>
#include <vector>
#include <string>
#include <fstream>
#include <map>

using namespace std;

class ASTNode {
public:
    virtual ~ASTNode() {}
    virtual string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp, int& temp_count, int& label_count) const = 0;
};

// Expression node types

class ExprNode : public ASTNode {
protected:
    string node_type; // Type information (int, float, void, etc.)
public:
    ExprNode(string type) : node_type(type) {}
    virtual string get_type() const { return node_type; }
};

// Variable node (for ID references)

class VarNode : public ExprNode {
private:
    string name;
    ExprNode* index; // For array access, nullptr for simple variables

public:
    VarNode(string name, string type, ExprNode* idx = nullptr)
        : ExprNode(type), name(name), index(idx) {}
    
    ~VarNode() { if(index) delete index; }
    
    bool has_index() const { return index != nullptr; }
    
    string generate_index_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                              int& temp_count, int& label_count) const {
        if (index == nullptr) {
            return "";
        }

        return index->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (has_index()) {
            string index_result = generate_index_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
            string result = "t" + to_string(temp_count++);
            outcode << result << " = " << name << "[" << index_result << "]\n";
            return result;
        }

        string result = "t" + to_string(temp_count++);

        // Reuse the first temporary associated with a simple variable.  The
        // temporary is intentionally reserved before this lookup to preserve
        // the numbering used by the supplied sample outputs.
        auto existing = symbol_to_temp.find(name);
        if (existing != symbol_to_temp.end()) {
            return existing->second;
        }

        outcode << result << " = " << name << "\n";
        symbol_to_temp[name] = result;
        return result;
    }
    
    string get_name() const { return name; }
};

// Constant node

class ConstNode : public ExprNode {
private:
    string value;

public:
    ConstNode(string val, string type) : ExprNode(type), value(val) {}
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        (void)symbol_to_temp;
        (void)label_count;

        string result = "t" + to_string(temp_count++);
        outcode << result << " = " << value << "\n";
        return result;
    }
};

// Binary operation node

class BinaryOpNode : public ExprNode {
private:
    string op;
    ExprNode* left;
    ExprNode* right;

public:
    BinaryOpNode(string op, ExprNode* left, ExprNode* right, string result_type)
        : ExprNode(result_type), op(op), left(left), right(right) {}
    
    ~BinaryOpNode() {
        delete left;
        delete right;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (left == nullptr || right == nullptr) {
            return "";
        }

        string left_result = left->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );
        string right_result = right->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );

        string result = "t" + to_string(temp_count++);
        outcode << result << " = " << left_result << " " << op << " "
                << right_result << "\n";
        return result;
    }
};

// Unary operation node

class UnaryOpNode : public ExprNode {
private:
    string op;
    ExprNode* expr;

public:
    UnaryOpNode(string op, ExprNode* expr, string result_type)
        : ExprNode(result_type), op(op), expr(expr) {}
    
    ~UnaryOpNode() { delete expr; }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (expr == nullptr) {
            return "";
        }

        string operand = expr->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );
        string result = "t" + to_string(temp_count++);
        outcode << result << " = " << op << operand << "\n";
        return result;
    }
};

// Assignment node

class AssignNode : public ExprNode {
private:
    VarNode* lhs;
    ExprNode* rhs;

public:
    AssignNode(VarNode* lhs, ExprNode* rhs, string result_type)
        : ExprNode(result_type), lhs(lhs), rhs(rhs) {}
    
    ~AssignNode() {
        delete lhs;
        delete rhs;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (lhs == nullptr || rhs == nullptr) {
            return "";
        }

        string rhs_result = rhs->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );

        if (lhs->has_index()) {
            string index_result = lhs->generate_index_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
            outcode << lhs->get_name() << "[" << index_result << "] = "
                    << rhs_result << "\n";
        } else {
            outcode << lhs->get_name() << " = " << rhs_result << "\n";
        }

        return rhs_result;
    }
};

// Statement node types

class StmtNode : public ASTNode {
public:
    virtual string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                                int& temp_count, int& label_count) const = 0;
};

// Expression statement node

class ExprStmtNode : public StmtNode {
private:
    ExprNode* expr;

public:
    ExprStmtNode(ExprNode* e) : expr(e) {}
    ~ExprStmtNode() { if(expr) delete expr; }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (expr == nullptr) {
            return "";
        }

        return expr->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );
    }
};

// Block (compound statement) node

class BlockNode : public StmtNode {
private:
    vector<StmtNode*> statements;

public:
    ~BlockNode() {
        for (auto stmt : statements) {
            delete stmt;
        }
    }
    
    void add_statement(StmtNode* stmt) {
        if (stmt) statements.push_back(stmt);
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        for (const auto* statement : statements) {
            if (statement != nullptr) {
                statement->generate_code(
                    outcode, symbol_to_temp, temp_count, label_count
                );
            }
        }

        return "";
    }
};

// If statement node

class IfNode : public StmtNode {
private:
    ExprNode* condition;
    StmtNode* then_block;
    StmtNode* else_block; // nullptr if no else part

public:
    IfNode(ExprNode* cond, StmtNode* then_stmt, StmtNode* else_stmt = nullptr)
        : condition(cond), then_block(then_stmt), else_block(else_stmt) {}
    
    ~IfNode() {
        delete condition;
        delete then_block;
        if (else_block) delete else_block;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (condition == nullptr) {
            return "";
        }

        string condition_result = condition->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );
        if (condition_result.empty()) {
            return "";
        }

        string then_label = "L" + to_string(label_count++);
        string else_label = "L" + to_string(label_count++);
        string end_label = "L" + to_string(label_count++);

        outcode << "if " << condition_result << " goto " << then_label << "\n";
        outcode << "goto " << else_label << "\n";
        outcode << then_label << ":\n";

        if (then_block != nullptr) {
            then_block->generate_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
        }

        outcode << "goto " << end_label << "\n";
        outcode << else_label << ":\n";
        if (else_block != nullptr) {
            else_block->generate_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
        }
        outcode << end_label << ":\n";

        return "";
    }
};

// While statement node

class WhileNode : public StmtNode {
private:
    ExprNode* condition;
    StmtNode* body;

public:
    WhileNode(ExprNode* cond, StmtNode* body_stmt)
        : condition(cond), body(body_stmt) {}
    
    ~WhileNode() {
        delete condition;
        delete body;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (condition == nullptr || body == nullptr) {
            return "";
        }

        string condition_label = "L" + to_string(label_count++);
        string body_label = "L" + to_string(label_count++);
        string end_label = "L" + to_string(label_count++);

        outcode << condition_label << ":\n";

        string condition_result = condition->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );
        if (condition_result.empty()) {
            return "";
        }

        outcode << "if " << condition_result << " goto " << body_label << "\n";
        outcode << "goto " << end_label << "\n";
        outcode << body_label << ":\n";
        body->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );
        outcode << "goto " << condition_label << "\n";
        outcode << end_label << ":\n";

        return "";
    }
};

// For statement node

class ForNode : public StmtNode {
private:
    // The grammar supplies expression_statement nodes for these two fields.
    // ASTNode keeps the representation correct for both empty and non-empty
    // expression statements.
    ASTNode* init;
    ASTNode* condition;
    ExprNode* update;
    StmtNode* body;

public:
    ForNode(ASTNode* init_expr, ASTNode* cond_expr, ExprNode* update_expr, StmtNode* body_stmt)
        : init(init_expr), condition(cond_expr), update(update_expr), body(body_stmt) {}
    
    ~ForNode() {
        if (init) delete init;
        if (condition) delete condition;
        if (update) delete update;
        delete body;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (init != nullptr) {
            init->generate_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
        }

        string condition_label = "L" + to_string(label_count++);
        string body_label = "L" + to_string(label_count++);
        string end_label = "L" + to_string(label_count++);

        outcode << condition_label << ":\n";

        string condition_result;
        if (condition != nullptr) {
            condition_result = condition->generate_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
        }

        // An empty condition in a for loop is treated as true.
        if (condition_result.empty()) {
            outcode << "goto " << body_label << "\n";
        } else {
            outcode << "if " << condition_result << " goto " << body_label << "\n";
            outcode << "goto " << end_label << "\n";
        }

        outcode << body_label << ":\n";
        if (body != nullptr) {
            body->generate_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
        }

        if (update != nullptr) {
            update->generate_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
        }

        outcode << "goto " << condition_label << "\n";
        outcode << end_label << ":\n";

        return "";
    }
};

// Return statement node

class ReturnNode : public StmtNode {
private:
    ExprNode* expr;

public:
    ReturnNode(ExprNode* e) : expr(e) {}
    ~ReturnNode() { if (expr) delete expr; }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (expr == nullptr) {
            outcode << "return\n";
            return "";
        }

        string result = expr->generate_code(
            outcode, symbol_to_temp, temp_count, label_count
        );
        outcode << "return";
        if (!result.empty()) {
            outcode << " " << result;
        }
        outcode << "\n";

        return "";
    }
};

// Declaration node

class DeclNode : public StmtNode {
private:
    string type;
    vector<pair<string, int>> vars; // Variable name and array size (0 for regular vars)

public:
    DeclNode(string t) : type(t) {}
    
    void add_var(string name, int array_size = 0) {
        vars.push_back(make_pair(name, array_size));
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        (void)symbol_to_temp;
        (void)temp_count;
        (void)label_count;

        for (const auto& variable : vars) {
            outcode << "// Declaration: " << type << " " << variable.first;
            if (variable.second > 0) {
                outcode << "[" << variable.second << "]";
            }
            outcode << "\n";
        }

        return "";
    }
    
    string get_type() const { return type; }
    const vector<pair<string, int>>& get_vars() const { return vars; }
};

// Function declaration node

class FuncDeclNode : public ASTNode {
private:
    string return_type;
    string name;
    vector<pair<string, string>> params; // Parameter type and name
    BlockNode* body;

public:
    FuncDeclNode(string ret_type, string n) : return_type(ret_type), name(n), body(nullptr) {}
    ~FuncDeclNode() { if (body) delete body; }
    
    void add_param(string type, string name) {
        params.push_back(make_pair(type, name));
    }
    
    void set_body(BlockNode* b) {
        body = b;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        // Temporaries for simple variable reads are local to each function.
        symbol_to_temp.clear();

        outcode << "// Function: " << return_type << " " << name << "(";
        for (size_t i = 0; i < params.size(); ++i) {
            if (i > 0) {
                outcode << ", ";
            }
            outcode << params[i].first << " " << params[i].second;
        }
        outcode << ")\n";

        if (body != nullptr) {
            body->generate_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
        }
        outcode << "\n";

        return "";
    }
};

// Helper class for function arguments

class ArgumentsNode : public ASTNode {
private:
    vector<ExprNode*> args;

public:
    ~ArgumentsNode() {
        // Don't delete args here - they'll be transferred to FuncCallNode
    }
    
    void add_argument(ExprNode* arg) {
        if (arg) args.push_back(arg);
    }
    
    ExprNode* get_argument(int index) const {
        if (index >= 0 && static_cast<size_t>(index) < args.size()) {
            return args[static_cast<size_t>(index)];
        }
        return nullptr;
    }
    
    size_t size() const {
        return args.size();
    }
    
    const vector<ExprNode*>& get_arguments() const {
        return args;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        // This node doesn't generate code directly
        (void)outcode;
        (void)symbol_to_temp;
        (void)temp_count;
        (void)label_count;
        return "";
    }
};

// Function call node

class FuncCallNode : public ExprNode {
private:
    string func_name;
    vector<ExprNode*> arguments;

public:
    FuncCallNode(string name, string result_type)
        : ExprNode(result_type), func_name(name) {}
    
    ~FuncCallNode() {
        for (auto arg : arguments) {
            delete arg;
        }
    }
    
    void add_argument(ExprNode* arg) {
        if (arg) arguments.push_back(arg);
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        for (const auto* argument : arguments) {
            if (argument == nullptr) {
                continue;
            }

            string argument_result = argument->generate_code(
                outcode, symbol_to_temp, temp_count, label_count
            );
            if (!argument_result.empty()) {
                outcode << "param " << argument_result << "\n";
            }
        }

        if (get_type() == "void") {
            outcode << "call " << func_name << ", " << arguments.size() << "\n";
            return "";
        }

        string result = "t" + to_string(temp_count++);
        outcode << result << " = call " << func_name << ", "
                << arguments.size() << "\n";
        return result;
    }
};

// Program node (root of AST)

class ProgramNode : public ASTNode {
private:
    vector<ASTNode*> units;

public:
    ~ProgramNode() {
        for (auto unit : units) {
            delete unit;
        }
    }
    
    void add_unit(ASTNode* unit) {
        if (unit) units.push_back(unit);
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        for (const auto* unit : units) {
            if (unit != nullptr) {
                unit->generate_code(
                    outcode, symbol_to_temp, temp_count, label_count
                );
            }
        }

        return "";
    }
};

#endif // AST_H
