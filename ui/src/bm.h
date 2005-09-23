#include <stdio.h>
#include <sys/types.h>

typedef struct bm_variable_data_S {
	char	*BM_VARIABLE_NAME;
	char	*BM_VARIABLE_DATA;
} bm_variable_data;

extern	bm_variable_data 	bm_config_data[];
typedef	unsigned short int	BM_Bool;

#define	BM_TRUE		1
#define	BM_FALSE	0
#define BM_NB_VARIABLE	26	
#define BM_BUFF_SIZE    1024

bm_variable_data* 
bm_load_conf(const char* conf_file);

void 
bm_free_config();

void 
bm_display_config();

char *
bm_read_variable_data(char *dest, FILE *file);

char *
bm_read_variable_name(char *dest, FILE *file);

BM_Bool 
bm_is_variable_name (const char *variable, int *index );

void 
strip_space(FILE *file);

void 
go_to_next_line(FILE *file);

BM_Bool 
read_export (FILE *file);
