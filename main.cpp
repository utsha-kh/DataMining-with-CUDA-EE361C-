#include <algorithm>
#include <cassert>
#include <fstream>
#include <iostream>
#include <numeric>
#include <sstream>
#include <vector>
#include "kmeans.cpp"
#include "parser.h"

int main (int argc, char** argv) {

    const char *filename = "input.txt";
    //char *filename = argv[0];
    Parser parser(filename);

    KMeans module(parser.rows, parser.cols, 2, parser.data);

    parser.print();

    return 0;

}