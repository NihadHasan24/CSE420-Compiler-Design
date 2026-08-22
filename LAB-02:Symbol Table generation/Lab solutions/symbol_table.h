#pragma once

#include "scope_table.h"

// The parser owns this stream. Scope creation/removal messages use it so the
// original no-argument interface can produce the required logfile output.
extern ofstream outlog;

class symbol_table
{
private:
    scope_table *current_scope;
    int bucket_count;
    int current_scope_id;

public:
    explicit symbol_table(int bucket_count);
    ~symbol_table();

    void enter_scope();
    void exit_scope();
    bool insert(symbol_info* symbol);
    bool remove(symbol_info* symbol);
    symbol_info* lookup(symbol_info* symbol) const;
    void print_current_scope();
    void print_current_scope(ofstream& output) const;
    void print_all_scopes(ofstream& output) const;

    scope_table* get_current_scope() const;
    int get_current_scope_id() const;

    symbol_table(const symbol_table&) = delete;
    symbol_table& operator=(const symbol_table&) = delete;
};

inline symbol_table::symbol_table(int bucket_count)
{
    this->bucket_count = bucket_count > 0 ? bucket_count : 1;
    current_scope = nullptr;
    current_scope_id = 0;

    // Every program starts in the global scope.
    enter_scope();
}

inline symbol_table::~symbol_table()
{
    // Destruction is intentionally silent. The parser closes the logfile
    // before a global symbol-table object may be destroyed.
    while (current_scope != nullptr)
    {
        scope_table *scope_to_delete = current_scope;
        current_scope = current_scope->get_parent_scope();
        delete scope_to_delete;
    }
}

inline void symbol_table::enter_scope()
{
    ++current_scope_id;
    current_scope = new scope_table(bucket_count, current_scope_id, current_scope);

    if (outlog.is_open())
    {
        outlog << "New ScopeTable with ID " << current_scope_id
               << " created" << endl << endl;
    }
}

inline void symbol_table::exit_scope()
{
    if (current_scope == nullptr)
    {
        return;
    }

    scope_table *scope_to_delete = current_scope;
    int removed_scope_id = scope_to_delete->get_unique_id();
    current_scope = scope_to_delete->get_parent_scope();
    delete scope_to_delete;

    if (outlog.is_open())
    {
        outlog << "Scopetable with ID " << removed_scope_id
               << " removed" << endl << endl;
    }
}

inline bool symbol_table::insert(symbol_info* symbol)
{
    if (current_scope == nullptr)
    {
        return false;
    }

    // Ownership transfers to the current scope only when this succeeds.
    return current_scope->insert_in_scope(symbol);
}

inline bool symbol_table::remove(symbol_info* symbol)
{
    if (current_scope == nullptr)
    {
        return false;
    }

    return current_scope->delete_from_scope(symbol);
}

inline symbol_info* symbol_table::lookup(symbol_info* symbol) const
{
    if (symbol == nullptr)
    {
        return nullptr;
    }

    scope_table *scope = current_scope;
    while (scope != nullptr)
    {
        symbol_info *found_symbol = scope->lookup_in_scope(symbol);
        if (found_symbol != nullptr)
        {
            return found_symbol;
        }

        scope = scope->get_parent_scope();
    }

    return nullptr;
}

inline void symbol_table::print_current_scope()
{
    print_current_scope(outlog);
}

inline void symbol_table::print_current_scope(ofstream& output) const
{
    if (current_scope != nullptr)
    {
        current_scope->print_scope_table(output);
    }
}

inline void symbol_table::print_all_scopes(ofstream& output) const
{
    output << "################################" << endl << endl;

    scope_table *scope = current_scope;
    while (scope != nullptr)
    {
        scope->print_scope_table(output);
        scope = scope->get_parent_scope();
    }

    output << "################################" << endl << endl;
}

inline scope_table* symbol_table::get_current_scope() const
{
    return current_scope;
}

inline int symbol_table::get_current_scope_id() const
{
    return current_scope == nullptr ? 0 : current_scope->get_unique_id();
}
