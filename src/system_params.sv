package system_params;

  parameter int H      = 8;
  parameter int W      = 8;
  parameter int C_IN   = 1;
  parameter int R      = 3;
  parameter int S      = 3;
  parameter int NF     = 4;
  parameter int STRIDE = 1;

  parameter int H_OUT = H - R + 1;      // 6
  parameter int W_OUT = W - S + 1;      // 6
  parameter int M     = H_OUT * W_OUT;  // 36
  parameter int K     = C_IN * R * S;   // 9

  // Rectangular core — no padding anywhere
  parameter int M_MAX = 36;
  parameter int K_MAX = 9;
  parameter int F_MAX = 4;

  parameter int M_W = $clog2(M_MAX);    // 6
  parameter int K_W = $clog2(K_MAX);    // 4
  parameter int F_W = $clog2(F_MAX);    // 2

  parameter int DATA_W = 8;
  parameter int ACC_W  = 20;            // provable bound still 19+1
  parameter int OUT_W  = 8;

  parameter int IFMAP_DEPTH = H * W;            // 64
  parameter int IF_AW = $clog2(IFMAP_DEPTH);    // 6
  parameter int MEMB_DEPTH  = K_MAX * F_MAX;    // 36
  parameter int MEMC_DEPTH  = M_MAX * F_MAX;    // 144
  parameter int OFMAP_DEPTH = M * NF;           // 144

  parameter int SHIFT_W = 5;

endpackage
