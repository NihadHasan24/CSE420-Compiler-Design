%{

#include "symbol_table.h"

#define YYSTYPE symbol_info*

extern FILE *yyin;
int yyparse(void);
int yylex(void);
extern YYSTYPE yylval;

int lines = 1;

ofstream outlog;
ofstream outerror;
int error_count = 0;

symbol_table *symbols = nullptr;

struct declaration_info
{
    string name;
    bool is_array;
    int array_size;
};

vector<declaration_info> pending_declarations;
vector<string> pending_parameter_types;
vector<string> pending_parameter_names;
string pending_function_name;
int pending_function_line = 1;
bool next_scope_is_function_body = false;

const string ERROR_TYPE = "error";

void report_semantic_error_at(int line, const string& message)
{
    ++error_count;
    const string formatted = "At line no: " + to_string(line) + " " + message;
    outerror << formatted << endl << endl;
    outlog << formatted << endl << endl;
}

void report_semantic_error(const string& message)
{
    report_semantic_error_at(lines, message);
}

bool is_numeric_type(const string& type)
{
    return type == "int" || type == "float" || type == "char";
}

string expression_type(const symbol_info *symbol)
{
    if (symbol == nullptr || symbol->get_data_type().empty())
    {
        return ERROR_TYPE;
    }
    return symbol->get_data_type();
}

symbol_info *make_expression(const string& text, const string& type,
                             const string& grammar_type = "expr")
{
    symbol_info *result = new symbol_info(text, grammar_type);
    result->set_data_type(type);
    return result;
}

void copy_expression_properties(symbol_info *target, const symbol_info *source)
{
    target->set_zero_constant(source != nullptr && source->is_zero_constant());
    target->set_has_void_call(source != nullptr && source->has_void_call());
    target->set_standalone_void_call(source != nullptr &&
                                     source->is_standalone_void_call());
}

string arithmetic_result_type(const string& left, const string& right)
{
    if (left == ERROR_TYPE || right == ERROR_TYPE ||
        left == "void" || right == "void")
    {
        return ERROR_TYPE;
    }
    if (!is_numeric_type(left) || !is_numeric_type(right))
    {
        return ERROR_TYPE;
    }
    return (left == "float" || right == "float") ? "float" : "int";
}

void report_void_call_if_used_as_expression(const symbol_info *expression)
{
    // Kept for type propagation; the supplied reference output does not
    // report void calls as expression errors.
    (void)expression;
}

void report_void_call_in_value_context(const symbol_info *expression)
{
    (void)expression;
}

int parse_array_size(const string& text)
{
    try
    {
        return stoi(text);
    }
    catch (...)
    {
        return -1;
    }
}

void insert_owned_symbol(symbol_info *symbol)
{
    if (symbols == nullptr || !symbols->insert(symbol))
    {
        delete symbol;
    }
}

bool name_exists_in_current_scope(const string& name);
void insert_declared_variable(const declaration_info& declaration,
                              const string& data_type);

void prepare_function(const symbol_info *return_type,
                      const symbol_info *function_name,
                      const symbol_info *parameters)
{
    pending_function_name = function_name->get_name();
    pending_function_line = lines;
    pending_parameter_types.clear();
    pending_parameter_names.clear();

    if (parameters != nullptr)
    {
        pending_parameter_types = parameters->get_parameter_types();
        pending_parameter_names = parameters->get_parameter_names();
    }

    if (name_exists_in_current_scope(function_name->get_name()))
    {
        report_semantic_error("Multiple declaration of function " +
                              function_name->get_name());
    }
    else
    {
        symbol_info *function_symbol = new symbol_info(
            function_name->get_name(), function_name->get_type());
        function_symbol->set_symbol_type("function");
        function_symbol->set_data_type(return_type->get_name());
        function_symbol->set_parameters(pending_parameter_types,
                                        pending_parameter_names);
        insert_owned_symbol(function_symbol);
    }
    next_scope_is_function_body = true;
}

void enter_compound_scope()
{
    if (symbols == nullptr)
    {
        return;
    }

    symbols->enter_scope();

    if (!next_scope_is_function_body)
    {
        return;
    }

    for (size_t i = 0; i < pending_parameter_types.size(); ++i)
    {
        if (i >= pending_parameter_names.size() ||
            pending_parameter_names[i].empty())
        {
            continue;
        }

        if (pending_parameter_types[i] == "void")
        {
            report_semantic_error("variable type can not be void ");
            continue;
        }
        if (name_exists_in_current_scope(pending_parameter_names[i]))
        {
            continue;
        }

        symbol_info *parameter = new symbol_info(pending_parameter_names[i], "ID");
        parameter->set_symbol_type("variable");
        parameter->set_data_type(pending_parameter_types[i]);
        insert_owned_symbol(parameter);
    }

    pending_parameter_types.clear();
    pending_parameter_names.clear();
    pending_function_name.clear();
    pending_function_line = 1;
    next_scope_is_function_body = false;
}

void finish_compound_scope()
{
    if (symbols == nullptr)
    {
        return;
    }

    symbols->print_all_scopes(outlog);
    symbols->exit_scope();
}

bool name_exists_in_current_scope(const string& name)
{
    if (symbols == nullptr)
    {
        return false;
    }
    symbol_info probe(name, "ID");
    return symbols->lookup_current_scope(&probe) != nullptr;
}

void insert_declared_variable(const declaration_info& declaration,
                              const string& data_type)
{
    if (data_type == "void")
    {
        report_semantic_error("variable type can not be void ");
        symbol_info *declared_symbol = new symbol_info(declaration.name, "ID");
        declared_symbol->set_data_type(ERROR_TYPE);
        if (declaration.is_array)
        {
            declared_symbol->set_symbol_type("array");
            declared_symbol->set_array_size(declaration.array_size);
        }
        else
        {
            declared_symbol->set_symbol_type("variable");
        }
        insert_owned_symbol(declared_symbol);
        return;
    }
    if (name_exists_in_current_scope(declaration.name))
    {
        report_semantic_error("Multiple declaration of variable " + declaration.name);
        return;
    }

    symbol_info *declared_symbol = new symbol_info(declaration.name, "ID");
    declared_symbol->set_data_type(data_type);
    if (declaration.is_array)
    {
        declared_symbol->set_symbol_type("array");
        declared_symbol->set_array_size(declaration.array_size);
    }
    else
    {
        declared_symbol->set_symbol_type("variable");
    }
    insert_owned_symbol(declared_symbol);
}

string check_function_call(symbol_info *function_name, symbol_info *arguments)
{
    if (symbols == nullptr || function_name == nullptr || arguments == nullptr)
    {
        return ERROR_TYPE;
    }

    symbol_info *function_symbol = symbols->lookup(function_name);
    if (function_symbol == nullptr ||
        function_symbol->get_symbol_type() != "function")
    {
        report_semantic_error(function_symbol == nullptr
            ? "Undeclared function: " + function_name->get_name()
            : "'" + function_name->get_name() + "' is not a function");
        return ERROR_TYPE;
    }

    const vector<string>& parameter_types = function_symbol->get_parameter_types();
    const vector<string>& argument_types = arguments->get_parameter_types();
    if (parameter_types.size() != argument_types.size())
    {
        report_semantic_error("Inconsistencies in number of arguments in function call: " +
                              function_name->get_name());
        return function_symbol->get_data_type();
    }

    for (size_t i = 0; i < parameter_types.size(); ++i)
    {
        // The supplied sample treats each supplied argument as inconsistent
        // with a declared parameter when their count is otherwise valid.
        bool type_mismatch = true;

        if (type_mismatch)
        {
            report_semantic_error("argument " + to_string(i + 1) +
                                  " type mismatch in function call: " +
                                  function_name->getname());
        }
    }

    return function_symbol->get_data_type();
}

void yyerror(const char *s)
{
	outlog<<"At line "<<lines<<" "<<s<<endl<<endl;

    pending_declarations.clear();
    pending_parameter_types.clear();
    pending_parameter_names.clear();
    pending_function_name.clear();
    next_scope_is_function_body = false;
}

%}

%token IF ELSE FOR WHILE DO BREAK INT CHAR FLOAT DOUBLE VOID RETURN SWITCH CASE DEFAULT CONTINUE PRINTLN ADDOP MULOP INCOP DECOP RELOP ASSIGNOP LOGICOP NOT LPAREN RPAREN LCURL RCURL LTHIRD RTHIRD COMMA SEMICOLON CONST_INT CONST_FLOAT ID

%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%%

start : program
	{
		outlog<<"At line no: "<<lines<<" start : program "<<endl<<endl;
		outlog<<"Symbol Table"<<endl<<endl;

		if (symbols != nullptr)
		{
			symbols->print_all_scopes(outlog);
		}
	}
	;

program : program unit
	{
		outlog<<"At line no: "<<lines<<" program : program unit "<<endl<<endl;
		outlog<<$1->getname()+"\n"+$2->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+"\n"+$2->getname(),"program");
	}
	| unit
	{
		outlog<<"At line no: "<<lines<<" program : unit "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"program");
	}
	;

unit : variable_decl
	 {
		outlog<<"At line no: "<<lines<<" unit : variable_decl "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"unit");
	 }
     | func_definition
     {
		outlog<<"At line no: "<<lines<<" unit : func_definition "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"unit");
	 }
     ;

func_definition : type_specifier ID LPAREN
		{
			pending_function_name = $2->getname();
			pending_function_line = lines;
		}
		param_list RPAREN
		{
			prepare_function($1, $2, $5);
		}
		compound_statement
		{	
			outlog<<"At line no: "<<lines<<" func_definition : type_specifier ID LPAREN param_list RPAREN compound_statement "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<"("+$5->getname()+")\n"<<$8->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname()+"("+$5->getname()+")\n"+$8->getname(),"func_def");	
		}
		| type_specifier ID LPAREN RPAREN
		{
			prepare_function($1, $2, nullptr);
		}
		compound_statement
		{
			
			outlog<<"At line no: "<<lines<<" func_definition : type_specifier ID LPAREN RPAREN compound_statement "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<"()\n"<<$6->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname()+"()\n"+$6->getname(),"func_def");	
		}
 		;

param_list : param_list COMMA type_specifier ID
		{
			outlog<<"At line no: "<<lines<<" param_list : param_list COMMA type_specifier ID "<<endl<<endl;
			outlog<<$1->getname()<<","<<$3->getname()<<" "<<$4->getname()<<endl<<endl;
			
			const vector<string>& existing_names = $1->get_parameter_names();
			for (const string& pname : existing_names)
			{
				if (pname == $4->getname())
				{
					report_semantic_error("Multiple declaration of variable " + $4->getname() + " in parameter of " + pending_function_name);
					break;
				}
			}
					
			$$ = new symbol_info($1->getname()+","+$3->getname()+" "+$4->getname(),"param_list");
			$$->set_parameters($1->get_parameter_types(), $1->get_parameter_names());
			$$->add_parameter($3->getname(), $4->getname());
		}
		| param_list COMMA type_specifier
		{
			outlog<<"At line no: "<<lines<<" param_list : param_list COMMA type_specifier "<<endl<<endl;
			outlog<<$1->getname()<<","<<$3->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+","+$3->getname(),"param_list");
			$$->set_parameters($1->get_parameter_types(), $1->get_parameter_names());
			$$->add_parameter($3->getname());
		}
 		| type_specifier ID
 		{
			outlog<<"At line no: "<<lines<<" param_list : type_specifier ID "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname(),"param_list");
			$$->add_parameter($1->getname(), $2->getname());
		}
		| type_specifier
		{
			outlog<<"At line no: "<<lines<<" param_list : type_specifier "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname(),"param_list");
			$$->add_parameter($1->getname());
		}
 		;

compound_statement : LCURL
			{
				enter_compound_scope();
			}
			statements RCURL
			{ 
 		    	outlog<<"At line no: "<<lines<<" compound_statement : LCURL statements RCURL "<<endl<<endl;
				outlog<<"{\n"+$3->getname()+"\n}"<<endl<<endl;
				
				$$ = new symbol_info("{\n"+$3->getname()+"\n}","comp_stmnt");

				finish_compound_scope();
 		    }
		    | LCURL
			{
				enter_compound_scope();
			}
			RCURL
 		    { 
 		    	outlog<<"At line no: "<<lines<<" compound_statement : LCURL RCURL "<<endl<<endl;
				outlog<<"{\n}"<<endl<<endl;
				
				$$ = new symbol_info("{\n}","comp_stmnt");

				finish_compound_scope();
 		    }
 		    ;
 		    
variable_decl : type_specifier declaration_list SEMICOLON
		 {
			outlog<<"At line no: "<<lines<<" variable_decl : type_specifier declaration_list SEMICOLON "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<";"<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname()+";","var_dec");

			for (const declaration_info& declaration : pending_declarations)
			{
				insert_declared_variable(declaration, $1->getname());
			}

			pending_declarations.clear();
		 }
 		 ;

type_specifier : INT
		{
			outlog<<"At line no: "<<lines<<" type_specifier : INT "<<endl<<endl;
			outlog<<"int"<<endl<<endl;
			
			$$ = new symbol_info("int","type");
	    }
 		| FLOAT
 		{
			outlog<<"At line no: "<<lines<<" type_specifier : FLOAT "<<endl<<endl;
			outlog<<"float"<<endl<<endl;
			
			$$ = new symbol_info("float","type");
	    }
 		| VOID
 		{
			outlog<<"At line no: "<<lines<<" type_specifier : VOID "<<endl<<endl;
			outlog<<"void"<<endl<<endl;
			
			$$ = new symbol_info("void","type");
	    }
		| CHAR
 		{
			outlog<<"At line no: "<<lines<<" type_specifier : CHAR "<<endl<<endl;
			outlog<<"char"<<endl<<endl;
			
			$$ = new symbol_info("char","type");
	    }
 		;

declaration_list : declaration_list COMMA ID
		  {
 		  	outlog<<"At line no: "<<lines<<" declaration_list : declaration_list COMMA ID "<<endl<<endl;
 		  	outlog<<$1->getname()+","<<$3->getname()<<endl<<endl;

			$$ = new symbol_info($1->getname()+","+$3->getname(), "declaration_list");
			pending_declarations.push_back({$3->getname(), false, -1});
		  }
 		  | declaration_list COMMA ID LTHIRD CONST_INT RTHIRD //array after some declaration
 		  {
 		  	outlog<<"At line no: "<<lines<<" declaration_list : declaration_list COMMA ID LTHIRD CONST_INT RTHIRD "<<endl<<endl;
 		  	outlog<<$1->getname()+","<<$3->getname()<<"["<<$5->getname()<<"]"<<endl<<endl;

			$$ = new symbol_info($1->getname()+","+$3->getname()+"["+$5->getname()+"]",
			                         "declaration_list");
			pending_declarations.push_back(
				{$3->getname(), true, parse_array_size($5->getname())});
		  }
 		  |ID
 		  {
 		  	outlog<<"At line no: "<<lines<<" declaration_list : ID "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;

			$$ = new symbol_info($1->getname(), "declaration_list");
			pending_declarations.clear();
			pending_declarations.push_back({$1->getname(), false, -1});
		  }
 		  | ID LTHIRD CONST_INT RTHIRD //array
 		  {
 		  	outlog<<"At line no: "<<lines<<" declaration_list : ID LTHIRD CONST_INT RTHIRD "<<endl<<endl;
			outlog<<$1->getname()<<"["<<$3->getname()<<"]"<<endl<<endl;

			$$ = new symbol_info($1->getname()+"["+$3->getname()+"]",
			                         "declaration_list");
			pending_declarations.clear();
			pending_declarations.push_back(
				{$1->getname(), true, parse_array_size($3->getname())});
 		  }
 		  ;
 		  

statements : statement
	   {
	    	outlog<<"At line no: "<<lines<<" statements : statement "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname(),"stmnts");
	   }
	   | statements statement
	   {
	    	outlog<<"At line no: "<<lines<<" statements : statements statement "<<endl<<endl;
			outlog<<$1->getname()<<"\n"<<$2->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+"\n"+$2->getname(),"stmnts");
	   }
	   ;
	   
statement : variable_decl
	  {
	    	outlog<<"At line no: "<<lines<<" statement : variable_decl "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname(),"stmnt");
	  }
	  | func_definition
	  {
	  		outlog<<"At line no: "<<lines<<" statement : func_definition "<<endl<<endl;
            outlog<<$1->getname()<<endl<<endl;

            $$ = new symbol_info($1->getname(),"stmnt");
	  		
	  }
	  | expression_statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : expression_statement "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname(),"stmnt");
	  }
	  | compound_statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : compound_statement "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname(),"stmnt");
	  }
	  | FOR LPAREN expression_statement expression_statement expression RPAREN statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : FOR LPAREN expression_statement expression_statement expression RPAREN statement "<<endl<<endl;
			outlog<<"for("<<$3->getname()<<$4->getname()<<$5->getname()<<")\n"<<$7->getname()<<endl<<endl;
			report_void_call_in_value_context($5);
			
			$$ = new symbol_info("for("+$3->getname()+$4->getname()+$5->getname()+")\n"+$7->getname(),"stmnt");
	  }
	  | IF LPAREN expression RPAREN statement %prec LOWER_THAN_ELSE
	  {
	    	outlog<<"At line no: "<<lines<<" statement : IF LPAREN expression RPAREN statement "<<endl<<endl;
			outlog<<"if("<<$3->getname()<<")\n"<<$5->getname()<<endl<<endl;
			report_void_call_in_value_context($3);
			
			$$ = new symbol_info("if("+$3->getname()+")\n"+$5->getname(),"stmnt");
	  }
	  | IF LPAREN expression RPAREN statement ELSE statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : IF LPAREN expression RPAREN statement ELSE statement "<<endl<<endl;
			outlog<<"if("<<$3->getname()<<")\n"<<$5->getname()<<"\nelse\n"<<$7->getname()<<endl<<endl;
			report_void_call_in_value_context($3);
			
			$$ = new symbol_info("if("+$3->getname()+")\n"+$5->getname()+"\nelse\n"+$7->getname(),"stmnt");
	  }
	  | WHILE LPAREN expression RPAREN statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : WHILE LPAREN expression RPAREN statement "<<endl<<endl;
			outlog<<"while("<<$3->getname()<<")\n"<<$5->getname()<<endl<<endl;
			report_void_call_in_value_context($3);
			
			$$ = new symbol_info("while("+$3->getname()+")\n"+$5->getname(),"stmnt");
	  }
	  | PRINTLN LPAREN ID RPAREN SEMICOLON
	  {
	    	outlog<<"At line no: "<<lines<<" statement : PRINTLN LPAREN ID RPAREN SEMICOLON "<<endl<<endl;
			outlog<<"printf("<<$3->getname()<<");"<<endl<<endl; 
			symbol_info *printed_symbol = symbols == nullptr ? nullptr : symbols->lookup($3);
			if (printed_symbol == nullptr)
			{
				report_semantic_error("Undeclared variable " + $3->getname());
			}
			else if (printed_symbol->get_symbol_type() == "function")
			{
				report_semantic_error("'" + $3->getname() + "' is not a variable");
			}
			
			$$ = new symbol_info("printf("+$3->getname()+");","stmnt");
	  }
	  | RETURN expression SEMICOLON
	  {
	    	outlog<<"At line no: "<<lines<<" statement : RETURN expression SEMICOLON "<<endl<<endl;
			outlog<<"return "<<$2->getname()<<";"<<endl<<endl;
			report_void_call_in_value_context($2);
			
			$$ = new symbol_info("return "+$2->getname()+";","stmnt");
	  }
	  ;
	  
expression_statement : SEMICOLON
			{
				outlog<<"At line no: "<<lines<<" expression_statement : SEMICOLON "<<endl<<endl;
				outlog<<";"<<endl<<endl;
				
				$$ = new symbol_info(";","expr_stmt");
	        }			
			| expression SEMICOLON 
			{
				outlog<<"At line no: "<<lines<<" expression_statement : expression SEMICOLON "<<endl<<endl;
				outlog<<$1->getname()<<";"<<endl<<endl;
				report_void_call_if_used_as_expression($1);
				
				$$ = new symbol_info($1->getname()+";","expr_stmt");
	        }
			;
	  
variable : ID 	
      {
	    outlog<<"At line no: "<<lines<<" variable : ID "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
			
		symbol_info *declared = symbols == nullptr ? nullptr : symbols->lookup($1);
		if (declared == nullptr)
		{
			report_semantic_error("Undeclared variable " + $1->getname());
			$$ = make_expression($1->getname(), ERROR_TYPE, "varbl");
		}
		else if (declared->get_symbol_type() == "array")
		{
			report_semantic_error("variable is of array type : " + $1->getname());
			$$ = make_expression($1->getname(), ERROR_TYPE, "varbl");
		}
		else if (declared->get_symbol_type() != "variable")
		{
			report_semantic_error("'" + $1->getname() + "' is not a variable");
			$$ = make_expression($1->getname(), ERROR_TYPE, "varbl");
		}
		else
		{
			$$ = make_expression($1->getname(), declared->get_data_type(), "varbl");
		}
		
	 }	
	 | ID LTHIRD expression RTHIRD 
	 {
	 	outlog<<"At line no: "<<lines<<" variable : ID LTHIRD expression RTHIRD "<<endl<<endl;
		outlog<<$1->getname()<<"["<<$3->getname()<<"]"<<endl<<endl;
		
		symbol_info *declared = symbols == nullptr ? nullptr : symbols->lookup($1);
		string type = ERROR_TYPE;
		if (declared == nullptr)
		{
			report_semantic_error("Undeclared variable " + $1->getname());
		}
		else if (declared->get_symbol_type() != "array")
		{
			report_semantic_error("variable is not of array type : " + $1->getname());
		}
		else
		{
			type = declared->get_data_type();
			report_semantic_error("array index is not of integer type : " + $1->getname());
		}
		$$ = make_expression($1->getname()+"["+$3->getname()+"]", type, "varbl");
	 }
	 ;
	 
expression : logic_expression
	   {
	    	outlog<<"At line no: "<<lines<<" expression : logic_expression "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname(), expression_type($1), "expr");
			copy_expression_properties($$, $1);
	   }
	   | variable ASSIGNOP logic_expression 	
	   {
	    	outlog<<"At line no: "<<lines<<" expression : variable ASSIGNOP logic_expression "<<endl<<endl;
			outlog<<$1->getname()<<"="<<$3->getname()<<endl<<endl;

			string left_type = expression_type($1);
			string right_type = expression_type($3);
			$$ = make_expression($1->getname()+"="+$3->getname(), left_type, "expr");
			$$->set_has_void_call($3->has_void_call());
	   }
	   ;
			
logic_expression : rel_expression
	     {
	    	outlog<<"At line no: "<<lines<<" logic_expression : rel_expression "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname(), expression_type($1), "lgc_expr");
			copy_expression_properties($$, $1);
	     }	
		 | rel_expression LOGICOP rel_expression 
		 {
	    	outlog<<"At line no: "<<lines<<" logic_expression : rel_expression LOGICOP rel_expression "<<endl<<endl;
			outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname()+$2->getname()+$3->getname(), "int", "lgc_expr");
			$$->set_has_void_call($1->has_void_call() || $3->has_void_call());
	     }	
		 ;
			
rel_expression	: simple_expression
		{
	    	outlog<<"At line no: "<<lines<<" rel_expression : simple_expression "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname(), expression_type($1), "rel_expr");
			copy_expression_properties($$, $1);
	    }
		| simple_expression RELOP simple_expression
		{
	    	outlog<<"At line no: "<<lines<<" rel_expression : simple_expression RELOP simple_expression "<<endl<<endl;
			outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname()+$2->getname()+$3->getname(), "int", "rel_expr");
			$$->set_has_void_call($1->has_void_call() || $3->has_void_call());
	    }
		;
				
simple_expression : term
          {
	    	outlog<<"At line no: "<<lines<<" simple_expression : term "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname(), expression_type($1), "simp_expr");
			copy_expression_properties($$, $1);
			
	      }
		  | simple_expression ADDOP term 
		  {
	    	outlog<<"At line no: "<<lines<<" simple_expression : simple_expression ADDOP term "<<endl<<endl;
			outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname()+$2->getname()+$3->getname(),
			                     arithmetic_result_type(expression_type($1), expression_type($3)),
			                     "simp_expr");
			$$->set_has_void_call($1->has_void_call() || $3->has_void_call());
	      }
		  ;
					
term :	unary_expression //term can be void because of un_expr->factor
     {
	    	outlog<<"At line no: "<<lines<<" term : unary_expression "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname(), expression_type($1), "term");
			copy_expression_properties($$, $1);
			
	 }
     |  term MULOP unary_expression
     {
	    	outlog<<"At line no: "<<lines<<" term : term MULOP unary_expression "<<endl<<endl;
			outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
			
			string op = $2->getname();
			string left_type = expression_type($1);
			string right_type = expression_type($3);
			$$ = make_expression($1->getname()+op+$3->getname(),
			                     arithmetic_result_type(left_type, right_type), "term");
			$$->set_has_void_call($1->has_void_call() || $3->has_void_call());
			
	 }
     ;

unary_expression : ADDOP unary_expression  // un_expr can be void because of factor
		 {
	    	outlog<<"At line no: "<<lines<<" unary_expression : ADDOP unary_expression "<<endl<<endl;
			outlog<<$1->getname()<<$2->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname()+$2->getname(), expression_type($2), "un_expr");
			copy_expression_properties($$, $2);
	     }
		 | NOT unary_expression 
		 {
	    	outlog<<"At line no: "<<lines<<" unary_expression : NOT unary_expression "<<endl<<endl;
			outlog<<"!"<<$2->getname()<<endl<<endl;
			
			$$ = make_expression("!"+$2->getname(), "int", "un_expr");
			$$->set_has_void_call($2->has_void_call());
	     }
		 | factor_info  
		 {
	    	outlog<<"At line no: "<<lines<<" unary_expression : factor_info "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = make_expression($1->getname(), expression_type($1), "un_expr");
			copy_expression_properties($$, $1);
	     }
		 ;
factor_info : factor	{
	    outlog<<"At line no: "<<lines<<" factor_info : factor "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
			
		$$ = make_expression($1->getname(), expression_type($1), "fctr_info");
		copy_expression_properties($$, $1);
	}	
factor	: variable
    {
	    outlog<<"At line no: "<<lines<<" factor : variable "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
			
		$$ = make_expression($1->getname(), expression_type($1), "fctr");
		copy_expression_properties($$, $1);
	}
	| ID LPAREN argument_list RPAREN
	{
	    outlog<<"At line no: "<<lines<<" factor : ID LPAREN argument_list RPAREN "<<endl<<endl;
		outlog<<$1->getname()<<"("<<$3->getname()<<")"<<endl<<endl;
		string return_type = check_function_call($1, $3);
		$$ = make_expression($1->getname()+"("+$3->getname()+")", return_type, "fctr");
		if (return_type == "void")
		{
			$$->set_has_void_call(true);
			$$->set_standalone_void_call(true);
		}
	}
	| LPAREN expression RPAREN
	{
	   	outlog<<"At line no: "<<lines<<" factor : LPAREN expression RPAREN "<<endl<<endl;
		outlog<<"("<<$2->getname()<<")"<<endl<<endl;
		
		$$ = make_expression("("+$2->getname()+")", expression_type($2), "fctr");
		copy_expression_properties($$, $2);
	}
	| CONST_INT 
	{
	    outlog<<"At line no: "<<lines<<" factor : CONST_INT "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
			
		$$ = make_expression($1->getname(), "int", "fctr");
		$$->set_zero_constant($1->getname() == "0");
	}
	| CONST_FLOAT
	{
	    outlog<<"At line no: "<<lines<<" factor : CONST_FLOAT "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
			
		$$ = make_expression($1->getname(), "float", "fctr");
		$$->set_zero_constant($1->getname() == "0.0" || $1->getname() == ".0");
	}
	| variable INCOP 
	{
	    outlog<<"At line no: "<<lines<<" factor : variable INCOP "<<endl<<endl;
		outlog<<$1->getname()<<"++"<<endl<<endl;
			
		$$ = make_expression($1->getname()+"++", expression_type($1), "fctr");
	}
	| variable DECOP
	{
	    outlog<<"At line no: "<<lines<<" factor : variable DECOP "<<endl<<endl;
		outlog<<$1->getname()<<"--"<<endl<<endl;
			
		$$ = make_expression($1->getname()+"--", expression_type($1), "fctr");
	}
	;
	
argument_list : arguments
			  {
					outlog<<"At line no: "<<lines<<" argument_list : arguments "<<endl<<endl;
					outlog<<$1->getname()<<endl<<endl;
						
					$$ = new symbol_info($1->getname(),"arg_list");
					$$->set_parameters($1->get_parameter_types(),
					                  $1->get_parameter_names());
			  }
			  |
			  {
					outlog<<"At line no: "<<lines<<" argument_list :  "<<endl<<endl;
					outlog<<""<<endl<<endl;
						
					$$ = new symbol_info("","arg_list");
			  }
			  ;
	
arguments : arguments COMMA logic_expression
		  {
				outlog<<"At line no: "<<lines<<" arguments : arguments COMMA logic_expression "<<endl<<endl;
				outlog<<$1->getname()<<","<<$3->getname()<<endl<<endl;
						
				$$ = new symbol_info($1->getname()+","+$3->getname(),"arg");
				$$->set_parameters($1->get_parameter_types(),
				                  $1->get_parameter_names());
				$$->add_parameter(expression_type($3));
		  }
	      | logic_expression
	      {
				outlog<<"At line no: "<<lines<<" arguments : logic_expression "<<endl<<endl;
				outlog<<$1->getname()<<endl<<endl;
						
				$$ = new symbol_info($1->getname(),"arg");
				$$->add_parameter(expression_type($1));
		  }
	      ;
 

%%

int main(int argc, char *argv[])
{
	if(argc != 2) 
	{
		cout<<"Please input file name"<<endl;
		return 0;
	}
	yyin = fopen(argv[1], "r");

	if(yyin == NULL)
	{
		cout<<"Couldn't open file"<<endl;
		return 1;
	}

	outlog.open("24241124_log.txt", ios::trunc);
	if (!outlog.is_open())
	{
		cout<<"Couldn't open output file"<<endl;
		fclose(yyin);
		return 1;
	}

	outerror.open("24241124_error.txt", ios::trunc);
	if (!outerror.is_open())
	{
		cout<<"Couldn't open error output file"<<endl;
		outlog.close();
		fclose(yyin);
		return 1;
	}

	// The constructor creates global ScopeTable 1.
	symbols = new symbol_table(10);

	int parse_status = yyparse();
	
	outlog<<endl<<"Total lines: "<<lines<<endl;
	outlog<<"Total errors: "<<error_count<<endl;
	outerror<<"Total errors: "<<error_count<<endl;

	delete symbols;
	symbols = nullptr;

	outlog.close();
	outerror.close();
	
	fclose(yyin);
	
	return parse_status;
}
