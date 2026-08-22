#pragma once

#include<bits/stdc++.h>
using namespace std;

class symbol_info
{
private:
    string name;
    string type;

    // Write necessary attributes to store what type of symbol it is (variable/array/function)
    // Write necessary attributes to store the type/return type of the symbol (int/float/void/...)
    // Write necessary attributes to store the parameters of a function
    // Write necessary attributes to store the array size if the symbol is an array
    string symbol_type;
    string data_type;
    vector<string> parameter_types;
    vector<string> parameter_names;
    int array_size;

public:
    symbol_info(string name, string type)
    {
        this->name = name;
        this->type = type;
        this->symbol_type = "";
        this->data_type = "";
        this->array_size = -1;
    }
    string get_name() const
    {
        return name;
    }
    string get_type() const
    {
        return type;
    }
    void set_name(string name)
    {
        this->name = name;
    }
    void set_type(string type)
    {
        this->type = type;
    }
    // Write necessary functions to set and get the attributes
    string get_symbol_type() const
    {
        return symbol_type;
    }
    void set_symbol_type(string symbol_type)
    {
        this->symbol_type = symbol_type;
    }
    string get_data_type() const
    {
        return data_type;
    }
    void set_data_type(string data_type)
    {
        this->data_type = data_type;
    }
    int get_array_size() const
    {
        return array_size;
    }
    void set_array_size(int array_size)
    {
        this->array_size = array_size;
    }
    const vector<string>& get_parameter_types() const
    {
        return parameter_types;
    }
    const vector<string>& get_parameter_names() const
    {
        return parameter_names;
    }
    int get_parameter_count() const
    {
        return static_cast<int>(parameter_types.size());
    }
    void set_parameter_types(vector<string> parameter_types)
    {
        this->parameter_types = parameter_types;
    }
    void set_parameter_names(vector<string> parameter_names)
    {
        this->parameter_names = parameter_names;
    }
    void set_parameters(vector<string> parameter_types, vector<string> parameter_names)
    {
        this->parameter_types = parameter_types;
        this->parameter_names = parameter_names;
        this->parameter_names.resize(parameter_types.size());
    }
    void add_parameter(string parameter_type, string parameter_name = "")
    {
        parameter_types.push_back(parameter_type);
        parameter_names.push_back(parameter_name);
    }

    string getname() const
    {
        return name;
    }
    string gettype() const
    {
        return type;
    }

    ~symbol_info()
    {
        // Write necessary code to deallocate memory, if necessary
    }
};
