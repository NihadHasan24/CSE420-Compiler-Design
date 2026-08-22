#pragma once

#include "symbol_info.h"

class scope_table
{
private:
    int bucket_count;
    int unique_id;
    scope_table *parent_scope = nullptr;
    vector<list<symbol_info *>> table;

    int hash_function(const string& name) const
    {
        // write your hash function here
        unsigned long long hash_value = 0;
        for (size_t i = 0; i < name.size(); i++)
        {
            hash_value += static_cast<unsigned char>(name[i]);
        }
        return hash_value % bucket_count;
    }

public:
    scope_table();
    scope_table(int bucket_count, int unique_id, scope_table *parent_scope);
    scope_table *get_parent_scope() const;
    int get_unique_id() const;
    symbol_info *lookup_in_scope(const symbol_info* symbol) const;

    // Ownership transfers to this scope only when insertion succeeds.
    // The caller remains responsible for the pointer when this returns false.
    bool insert_in_scope(symbol_info* symbol);
    bool delete_from_scope(const symbol_info* symbol);
    void print_scope_table(ofstream& outlog);
    ~scope_table();

    scope_table(const scope_table&) = delete;
    scope_table& operator=(const scope_table&) = delete;

    // you can add more methods if you need
};

// complete the methods of scope_table class
inline scope_table::scope_table()
{
    bucket_count = 1;
    unique_id = 0;
    parent_scope = nullptr;
    table.resize(bucket_count);
}

inline scope_table::scope_table(int bucket_count, int unique_id, scope_table *parent_scope)
{
    this->bucket_count = bucket_count > 0 ? bucket_count : 1;
    this->unique_id = unique_id;
    this->parent_scope = parent_scope;
    table.resize(this->bucket_count);
}

inline scope_table *scope_table::get_parent_scope() const
{
    return parent_scope;
}

inline int scope_table::get_unique_id() const
{
    return unique_id;
}

inline symbol_info *scope_table::lookup_in_scope(const symbol_info* symbol) const
{
    if (symbol == nullptr)
    {
        return nullptr;
    }

    int bucket_no = hash_function(symbol->get_name());
    for (symbol_info *current_symbol : table[bucket_no])
    {
        if (current_symbol->get_name() == symbol->get_name())
        {
            return current_symbol;
        }
    }

    return nullptr;
}

inline bool scope_table::insert_in_scope(symbol_info* symbol)
{
    if (symbol == nullptr || symbol->get_name().empty())
    {
        return false;
    }

    if (lookup_in_scope(symbol) != nullptr)
    {
        return false;
    }

    int bucket_no = hash_function(symbol->get_name());
    table[bucket_no].push_back(symbol);
    return true;
}

inline bool scope_table::delete_from_scope(const symbol_info* symbol)
{
    if (symbol == nullptr)
    {
        return false;
    }

    int bucket_no = hash_function(symbol->get_name());
    for (list<symbol_info *>::iterator it = table[bucket_no].begin();
         it != table[bucket_no].end(); it++)
    {
        if ((*it)->get_name() == symbol->get_name())
        {
            delete *it;
            table[bucket_no].erase(it);
            return true;
        }
    }

    return false;
}

inline void scope_table::print_scope_table(ofstream& outlog)
{
    outlog << "ScopeTable # " << unique_id << endl;

    //iterate through the current scope table and print the symbols and all relevant information
    for (int i = 0; i < bucket_count; i++)
    {
        if (table[i].empty())
        {
            continue;
        }

        outlog << i << " --> " << endl;

        for (symbol_info *symbol : table[i])
        {
            outlog << "< " << symbol->get_name() << " : "
                   << symbol->get_type() << " >" << endl;

            string symbol_type = symbol->get_symbol_type();

            if (symbol_type == "variable" || symbol_type == "Variable")
            {
                outlog << "Variable" << endl;
                outlog << "Type: " << symbol->get_data_type() << endl << endl;
            }
            else if (symbol_type == "array" || symbol_type == "Array")
            {
                outlog << "Array" << endl;
                outlog << "Type: " << symbol->get_data_type() << endl;
                outlog << "Size: " << symbol->get_array_size() << endl << endl;
            }
            else if (symbol_type == "function" || symbol_type == "Function" ||
                     symbol_type == "function_definition" ||
                     symbol_type == "Function Definition")
            {
                outlog << "Function Definition" << endl;
                outlog << "Return Type: " << symbol->get_data_type() << endl;
                outlog << "Number of Parameters: "
                       << symbol->get_parameter_count() << endl;
                outlog << "Parameter Details: ";

                const vector<string> &parameter_types = symbol->get_parameter_types();
                const vector<string> &parameter_names = symbol->get_parameter_names();

                for (size_t j = 0; j < parameter_types.size(); j++)
                {
                    if (j > 0)
                    {
                        outlog << ", ";
                    }

                    outlog << parameter_types[j];
                    if (j < parameter_names.size() && parameter_names[j] != "")
                    {
                        outlog << " " << parameter_names[j];
                    }
                }
                outlog << endl;
            }
        }
    }

    outlog << endl;
}

inline scope_table::~scope_table()
{
    for (int i = 0; i < bucket_count; i++)
    {
        for (symbol_info *symbol : table[i])
        {
            delete symbol;
        }
        table[i].clear();
    }
    table.clear();
}
