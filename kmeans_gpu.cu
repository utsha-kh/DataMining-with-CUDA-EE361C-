#include <iostream>
#include <chrono>
#include <iomanip>
#include <cfloat>
#include <cmath>
#include <cuda.h>
#include "kmeans_gpu.h"
#include "parser.h"

int n;  // number of data points
int d;  // dimention of input data (usually 2, for 2D data)
int k;  // number of clusters

__device__ void d_getDistance(float* x1, float* x2, float *ret, int n, int d, int k);
__global__ void d_getMSE(float* dataPoints, int* labels, float* centeroids, float* ret, int n, int d, int k);
__global__ void d_assignDataPoints(float* dataPoints, int* labels, float* centeroids, int n, int d, int k);

// return L2 distance between 2 points
__device__ void d_getDistance(float* x1, float* x2, float *ret, int n, int d, int k){
	float dist = 0;
    for(int i = 0; i < d; i++){
        dist += (x2[i] - x1[i]) * (x2[i] - x1[i]);
    }
    *ret = dist; 
}

// return current Mean Squared Error value of all points. This is needed to detect convergence, but not essential in k-means algorithm.
float getMSE(float** dataPoints, int* labels, float** centeroids){

    float error = 0;
    float* err = new float[n];  // distance between each dataPoints to centeroids
    float *d_dataPoints, *d_centeroids, *d_err; 
    int *d_labels;

    // Allocate memory on GPU
    cudaMalloc(&d_dataPoints, sizeof(float) * n * d);
    cudaMalloc(&d_labels, sizeof(int) * n);
    cudaMalloc(&d_centeroids, sizeof(float) * k * d);
    cudaMalloc(&d_err, sizeof(float) * n);    

    // Flattening both matrix to ease copying to GPU
    float* flattenDataPoints = new float[n * d];
    for(int i = 0; i < n; i++){
        for(int j = 0; j < d; j++){
            flattenDataPoints[i * d + j] = dataPoints[i][j];
        }
    }
    float* flattenCenteroids = new float[n * k];
    for(int i = 0; i < k; i++){
        for(int j = 0; j < d; j++){
            flattenCenteroids[i * d + j] = centeroids[i][j];
        }
    }

    // copy flattened data into GPU
    cudaMemcpy(d_dataPoints, flattenDataPoints, sizeof(float) * n * d, cudaMemcpyHostToDevice);
    cudaMemcpy(d_labels, labels, sizeof(int) * n, cudaMemcpyHostToDevice);
    cudaMemcpy(d_centeroids, flattenCenteroids, sizeof(float) * k * d, cudaMemcpyHostToDevice);
    
    // call the kernel function to compute RMSE values in parallel
    int block_size = n / THREAD_PER_BLOCK + (n % THREAD_PER_BLOCK != 0);
    d_getMSE<<<block_size, THREAD_PER_BLOCK>>>(d_dataPoints, d_labels, d_centeroids, d_err, n, d, k);
    cudaDeviceSynchronize();

    // copy back the result from GPU to CPU
    cudaMemcpy(err, d_err, sizeof(float) * n, cudaMemcpyDeviceToHost);

    // Summing up computed errors. could be made faster by parallel reduction
    for(int i = 0; i < n; i++){
        error += err[i];
        //std::cout << "error[" << i << "] = " << err[i] << std::endl;
    }

    // deallocate GPU and CPU memory
    cudaFree(d_dataPoints);
    cudaFree(d_labels);
    cudaFree(d_centeroids);
    cudaFree(d_err);
    delete[] flattenDataPoints;
    delete[] flattenCenteroids;

    // return actual Mean of Squared Errors.
    return error / n;
}

// kernel of above function. NOTE: this is like helper of RMSE. The error values stored in err[] still needs to be summed up.
__global__ void d_getMSE(float* dataPoints, int* labels, float* centeroids, float* err, int n, int d, int k){
    int id = blockIdx.x * blockDim.x + threadIdx.x;
    if(id >= n) return;
    d_getDistance(&dataPoints[id * d], &centeroids[labels[id] * d], &err[id], n, d, k); 
}

// initialize each center values u_i to a randomly chosen data point
void initCenters(float** dataPoints, float** centeroids){
    // Each center u[i] should be a random data point x[j], but 
    // generating a non-repeated random number isn't straightforward
    // so I'll do it later
    for(int i = 0; i < k; i++){
        for(int j = 0; j < d; j++){
            centeroids[i][j] = dataPoints[i][j];
        }
    } 
}

// Assign each data point to the closest centeroid, and store the result in *labels
void assignDataPoints(float** dataPoints, int* labels, float** centeroids){

    float *d_dataPoints, *d_centeroids; 
    int *d_labels;

    // Allocate memory on GPU
    cudaMalloc(&d_dataPoints, sizeof(float) * n * d);
    cudaMalloc(&d_labels, sizeof(int) * n);
    cudaMalloc(&d_centeroids, sizeof(float) * k * d);    

    // Flattening both matrix to ease copying to GPU
    float* flattenDataPoints = new float[n * d];
    for(int i = 0; i < n; i++){
        for(int j = 0; j < d; j++){
            flattenDataPoints[i * d + j] = dataPoints[i][j];
        }
    }
    float* flattenCenteroids = new float[n * k];
    for(int i = 0; i < k; i++){
        for(int j = 0; j < d; j++){
            flattenCenteroids[i * d + j] = centeroids[i][j];
        }
    }

    // copy flattened data into GPU
    cudaMemcpy(d_dataPoints, flattenDataPoints, sizeof(float) * n * d, cudaMemcpyHostToDevice);
    cudaMemcpy(d_labels, labels, sizeof(int) * n, cudaMemcpyHostToDevice);
    cudaMemcpy(d_centeroids, flattenCenteroids, sizeof(float) * k * d, cudaMemcpyHostToDevice);
    
    // call the kernel function to compute RMSE values in parallel
    int block_size = n / THREAD_PER_BLOCK + (n % THREAD_PER_BLOCK != 0);
    d_assignDataPoints<<<block_size, THREAD_PER_BLOCK>>>(d_dataPoints, d_labels, d_centeroids, n, d, k);
    cudaDeviceSynchronize();

    // copy back the result from GPU to CPU
    cudaMemcpy(labels, d_labels, sizeof(int) * n, cudaMemcpyDeviceToHost);

    // deallocate GPU memory
    cudaFree(d_dataPoints);
    cudaFree(d_labels);
    cudaFree(d_centeroids);
    delete[] flattenDataPoints;
    delete[] flattenCenteroids;
}

// kernal of above function
__global__ void d_assignDataPoints(float* dataPoints, int* labels, float* centeroids, int n, int d, int k){
    int id = blockIdx.x * blockDim.x + threadIdx.x;
    if(id >= n) return;
    int closest = 0;
    float minDistance = FLT_MAX;
    float dist_i = 0;
    // find the closest centeroid (centeroids[closest]) from this dataPoint (&dataPoint[id * d])
    for(int i = 0; i < k; i++){
        d_getDistance(&dataPoints[id * d], &centeroids[i * d], &dist_i, n, d, k);
        if(dist_i < minDistance){
            closest = i;
            minDistance = dist_i;
        }
    }
    labels[id] = closest;
}

// add two vectors
__global__ void d_addVector(float* x1, float* x2, float* ret){
    int id = blockIdx.x * blockDim.x + threadIdx.x;
    if (id >= 1000) return;
    ret[id] = x1[id] + x2[id];
}

void addVector(float* x1, float* x2, float* ret){
    for(int i = 0 ; i < d; i++){
        ret[i] = x1[i] + x2[i];
    }
}

// divide vector by scaler
__global__ void d_divideVector(float* x, int s, float* ret){
    int id = blockIdx.x * blockDim.x + threadIdx.x;
    if(id >= 1000) return;
    ret[id] = x[id] / (float)s;
}

void divideVector(float* x, int s, float* ret){
    for(int i = 0; i < d; i++){
        ret[i] = x[i] / (float)s;
    }
}

// Update each center of sets u_i to the average of all data points who belong to that set
void updateCenteroids(float** dataPoints, int* labels, float** centeroids){
    int count = 0;
    for(int i = 0; i < k; i++){
        float* sum = new float[d];
        for(int l = 0; l < d; l++) sum[l] = 0;
        for(int j = 0; j < n; j++){
            if(labels[j] == i){
                addVector(sum, dataPoints[j], sum);
                count++;
            }
        }
        divideVector(sum, count, centeroids[i]);
        delete[] sum;
    }

    float *d_dataPoints, *d_centeroids; 
    int *d_labels;
    int *d_centeroids_sizes;
    int *centeroids_sizes = new int[k]; // how many data points are avergaged to count each centeroid

    // Allocate memory on GPU
    cudaMalloc(&d_dataPoints, sizeof(float) * n * d);
    cudaMalloc(&d_labels, sizeof(int) * n);
    cudaMalloc(&d_centeroids, sizeof(float) * k * d);    
    cudaMalloc(&d_centeroids_sizes, sizeof(int) * k);

    // Flattening both matrix to ease copying to GPU
    float* flattenDataPoints = new float[n * d];
    for(int i = 0; i < n; i++){
        for(int j = 0; j < d; j++){
            flattenDataPoints[i * d + j] = dataPoints[i][j];
        }
    }
    float* flattenCenteroids = new float[n * k];
    for(int i = 0; i < k; i++){
        for(int j = 0; j < d; j++){
            flattenCenteroids[i * d + j] = 0; // reset values before passing to GPU. centeroids[i][j];
        }
    }
    for(int i = 0; i < k; i++){
        centeroids_sizes[i] = 0;    // reset values before passing to GPU. 
    }

    // copy flattened data into GPU
    cudaMemcpy(d_dataPoints, flattenDataPoints, sizeof(float) * n * d, cudaMemcpyHostToDevice);
    cudaMemcpy(d_labels, labels, sizeof(int) * n, cudaMemcpyHostToDevice);
    cudaMemcpy(d_centeroids, flattenCenteroids, sizeof(float) * k * d, cudaMemcpyHostToDevice);
    cudaMemcpy(d_centeroid_sizes, centeroids_sizes, sizeof(int) * k, cudaMemcpyHostToDevice);

    // call the kernel function to compute RMSE values in parallel
    // Here, I'm using 2D threads to parallelize double for loop so O(n * k) becomes O(1).
    int block_row_size = THREAD_PER_BLOCK / k;  //e.g. if k == 3, this is 1024 / 3 = 341
    int block_col_size = k;
    int number_of_blocks = n / block_row_size + (n % block_row_size != 0);
        // when k = 3, a block's shape will be 341 x 3 x 1, so it will have 1023 threads in a block, with 2 index per block
    dim3 block_shape(block_row_size, block_col_size, 1);
    d_updateCenteroids<<< number_of_blocks, block_shape >>(d_dataPoints, d_labels, d_centeroids, d_centeroid_sizes, n, d, k);
    cudaDeviceSynchronize();

    // copy back the result from GPU to CPU
    cudaMemcpy(flattenCenteroids, d_centeroids, sizeof(float) * k * d, cudaMemcpyDeviceToHost);
    cudaMemcpy(centeroids_sizes, d_centeroid_sizes, sizeof(int) * k, cudaMemcpyDeviceToHost);

    // put the flattened form of centeroids back to matrix
    for(int i = 0; i < k; i++){
        for(int j = 0; j < d; j++){
            centeroids[i][j] = flattenCenteroids[i * d + j];
        }
    }

    // the centeroids computed by GPU was just sum of all points. Still needs to be divided by counts. 
    for(int i = 0; i < k; i++){
        divideVector(centeroids[i], centeroids_sizes[i], centeroids[i]);
    }

    // deallocate GPU memory
    cudaFree(d_dataPoints);
    cudaFree(d_labels);
    cudaFree(d_centeroids);
    cudaFree(d_centeroid_sizes);
    delete[] flattenDataPoints;
    delete[] flattenCenteroids;
    delete[] centeroids_sizes;
}

// kernel of above function
__global__ void d_updateCenteroids(float* dataPoints, int* labels, float* centeroids, int* centeroids_sizes, int n, int d, int k){
        // Here, each thread has a 2D index (id_x, id_y). Range: id_x = [0, n -1], id_y = [0, k -1]. 
    int id_x = blockIdx.x * blockDim.x + threadIdx.x;
    int id_y = blockIdx.y * blockDim.y + threadIdx.y;
    if(id_x >= n || id_y >= k) return;
        // if, the data Point at id_x belongs to the id_y-th centeroid
    if(labels[id_x] == id_y){
        for(int i = 0; i < d; i++){
            atomicADD(&centeroids[id_y * d + i], dataPoints[id_x * d + i]);
            atomicADD(&centeroids_sizes[id_y], 1);
        }
    }
}

float myAbs(float a, float b){
    if(a > b)
        return a - b;
    else
        return b - a;
}

// Checks convergence (d/dt < 0.5%)
bool hasConverged(float prevError, float currentError){
    return myAbs(prevError, currentError) / prevError < 0.005;
}

// Calling this function will do everything for the user
void kMeansClustering(float** dataPoints, int* labels, int n_, int d_, int k_){
    n = n_; d = d_; k = k_; // copy arguments to global variables

    float** centeroids = new float*[k];
    for(int i = 0; i < k; i++){
        centeroids[i] = new float[d];
    }

    initCenters(dataPoints, centeroids);

    int iterations = 0;
    float previousError = FLT_MAX;
    float currentError = 0;
    while(iterations < MAX_ITERATIONS){    
        assignDataPoints(dataPoints, labels, centeroids);
        updateCenteroids(dataPoints, labels, centeroids);
        currentError = getMSE(dataPoints, labels, centeroids);
        if(hasConverged(previousError, currentError)) break;
        previousError = currentError;
        iterations++;
        std::cout << "Total Error Now: " << std::setprecision(6) << currentError << std::endl;
    }
    std::cout << "# of iterations: " << iterations << std::endl;

    // free memory
    for(int i = 0; i < k; i++){
        delete[] centeroids[i];
    }
    delete[] centeroids;
}

