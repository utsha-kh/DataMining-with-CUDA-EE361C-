#ifndef __PARSER__H
#define __PARSER__H

#include <vector>

class Parser{
public:
    std::vector<std::vector<float>> data;
    int rows; 
    int cols; 

    Parser(int rows, int cols);
    Parser(const char* filename);
 
    void print(void);
   
private:
    int getRowSize(const char* str_array);
    int getColSize(const char* str_array);

}; 

#endif
