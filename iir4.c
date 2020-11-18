// This file is part of the ZDAC reference implementation
// Author (2020) Marc René Schädler (suaefar@googlemail.com)

#include "mex.h"
#include <math.h>

void mexFunction (int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {
  mwIndex i, j, k, l, o1, o2, o3;
  mwSize M, N;
  mwSize *dims;
  float *b0r, *b0i, *a1r, *a1i, *inr, *ini, *outr, *outi;  
  float b0r_tmp, b0i_tmp, a1r_tmp, a1i_tmp;

  /* Get input pointers */
  b0r = (float*) mxGetPr (prhs[0]);
  b0i = (float*) mxGetPi (prhs[0]);

  a1r = (float*) mxGetPr (prhs[1]);
  a1i = (float*) mxGetPi (prhs[1]);

  inr = (float*) mxGetPr (prhs[2]);
  ini = (float*) mxGetPi (prhs[2]);

  // Get output dimensions
  M = mxGetM (prhs[2]);
  N = mxGetM (prhs[0]);

  /* Allocate memory for output */
  dims = (mwSize *) mxMalloc (2 * sizeof (mwSize));
  dims[0] = M;
  dims[1] = N;
  plhs[0] = (mxArray *) mxCreateNumericArray (2, dims, mxSINGLE_CLASS, mxCOMPLEX);

  /* Get output pointers */
  outr = (float *) mxGetPr (plhs[0]);
  outi = (float *) mxGetPi (plhs[0]);

  for (j = 0; j < N; j++) {
    b0r_tmp = b0r[j];
    b0i_tmp = b0i[j];
    a1r_tmp = a1r[j];
    a1i_tmp = a1i[j];
    o1 = j*M;
    for (i = 4; i < M; i++) {
      k = i+o1;
      // Apply phase and gain of b0
      outr[k] = b0r_tmp*inr[i] - b0i_tmp*ini[i];
      outi[k] = b0i_tmp*inr[i] + b0r_tmp*ini[i];
      // Add recursive parts - fourth order
      for (l = 0; l < 4; l++) {
        o2 = k-l;
        o3 = o2-1;
        outr[o2] += a1r_tmp*outr[o3] - a1i_tmp*outi[o3];
        outi[o2] += a1i_tmp*outr[o3] + a1r_tmp*outi[o3];
      }
    }
  }
}

