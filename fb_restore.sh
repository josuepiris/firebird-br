#!/bin/bash

	SCRIPT_BKP="employee.sh"		# Nome do script gerador dos arquivos de backups
	ORIGEM_BKP=/mnt/backups/employee	# Pasta "raiz" onde há subpastas p/ cada banco de dados
	DESTINO_BKP=/opt/firebird/data		# Pasta onde serão criados o arquivo do banco de dados restaurado

	bkp_antigo ()
	{

		FILES=`ls *\.tar\.xz | sort -r`

		if [ -n "$FILES" ]
		then

			ARQUIVO_TAR=$(whiptail --backtitle "Firebird Backup Management Tool" --title "Selecionar Arquivo" --menu "\nSelecione o arquivo correspondente a \"data\" do backup..." --ok-button "Selecionar" --cancel-button "Cancelar" 14 60 5 `for FILE in ${FILES[@]}; do echo $FILE "-"; done` 3>&1 1>&2 2>&3)

			if [ $? -eq 0 ]
			then

				AUX01=`echo "$ARQUIVO_TAR" | cut -d . -f 1`

				echo -e "`date +"%d %b %Y %T"` - Obtendo lista de arquivos do \"$ARQUIVO_TAR\"... Por favor, aguarde!"
				test -e ${AUX01}.lst && FILES=`cat ${AUX01}.lst | grep ^"${SELECTED_DB}-incr"` || exit

				if [ -n "$FILES" ]
				then

					ARQUIVO_NBK=$(whiptail --backtitle "Firebird Backup Management Tool" --title "Selecionar Arquivo" --menu "\nSelecione o arquivo correspondente a \"data/hora\" do backup..." --ok-button "Selecionar" --cancel-button "Cancelar" 14 65 5 `for FILE in ${FILES[@]}; do echo $FILE "-"; done` 3>&1 1>&2 2>&3)

					if [ $? -eq 0 ]
					then

						ANO=`echo "$ARQUIVO_NBK" | cut -d - -f 3 | sed -r 's/(.{4})(.{2})(.{2})(.{2})(.{2}).*/\1/'`
						MES=`echo "$ARQUIVO_NBK" | cut -d - -f 3 | sed -r 's/(.{4})(.{2})(.{2})(.{2})(.{2}).*/\2/'`
						DIA=`echo "$ARQUIVO_NBK" | cut -d - -f 3 | sed -r 's/(.{4})(.{2})(.{2})(.{2})(.{2}).*/\3/'`
						HORA=`echo "$ARQUIVO_NBK" | cut -d - -f 3 | sed -r 's/(.{4})(.{2})(.{2})(.{2})(.{2}).*/\4/'`
						MINUTOS=`echo "$ARQUIVO_NBK" | cut -d - -f 3 | sed -r 's/(.{4})(.{2})(.{2})(.{2})(.{2}).*/\5/'`

						echo -e "\n`date +"%d %b %Y %T"` - Verificar e confirmar o backup a ser restaurado...\n"

						echo -e "\tData/Hora do Backup:\t${DIA}/${MES}/${ANO} ${HORA}:${MINUTOS}"
						echo -e "\tDatabase Original:\t${DESTINO_BKP}/${SELECTED_DB}.fdb"
						echo -e "\tRestaurar para:\t\t${DESTINO_BKP}/bkp-${SELECTED_DB}-${ANO}${MES}${DIA}${HORA}${MINUTOS}.fdb\n"

						echo -ne "Deseja continuar?! (Case-sensitive) [y|N]: "
						read OPT

						if [ -n "$OPT" ] && [ "$OPT" == "y" ]
						then

							echo -e "\n`date +"%d %b %Y %T"` - Criando diretório temporário (tmp) em \"${ORIGEM_BKP}/${SELECTED_DB}\"..."
							mkdir tmp || exit

							echo "`date +"%d %b %Y %T"` - Extraindo conteúdo do arquivo \"$ARQUIVO_TAR\" p/ o diretório \"tmp\"..."
							tar -Jxf $ARQUIVO_TAR -C ./tmp || exit

							echo "`date +"%d %b %Y %T"` - Gerando lista de arquivos do \"nbackup\"..."
							cat ${AUX01}.lst | grep ^"${SELECTED_DB}-full" > ./tmp/nbackup.lst || exit

							while read file
							do

								echo $file >>./tmp/nbackup.lst || exit
								test "`basename $file`" = "$ARQUIVO_NBK" && break

							done < <(ls ./tmp/*.nbk)

							echo -e "`date +"%d %b %Y %T"` - Restaurando o backup selecionado p/ \"${DESTINO_BKP}/bkp-${SELECTED_DB}-${ANO}${MES}${DIA}${HORA}${MINUTOS}.fdb\"..." | tee ${WORK_DIR}/$(basename $0 | cut -d . -f 1).log
							nbackup -R ${DESTINO_BKP}/bkp-${SELECTED_DB}-${ANO}${MES}${DIA}${HORA}${MINUTOS}.fdb $(<./tmp/nbackup.lst) || exit

							echo -e "`date +"%d %b %Y %T"` - Atribuindo permissões ao \"${DESTINO_BKP}/bkp-${SELECTED_DB}-${ANO}${MES}${DIA}${HORA}${MINUTOS}.fdb\"..."
							chgrp firebird ${DESTINO_BKP}/bkp-${SELECTED_DB}-${ANO}${MES}${DIA}${HORA}${MINUTOS}.fdb || exit
							chmod g+w ${DESTINO_BKP}/bkp-${SELECTED_DB}-${ANO}${MES}${DIA}${HORA}${MINUTOS}.fdb || exit

							echo -e "`date +"%d %b %Y %T"` - Removendo arquivos temporários..."
							rm tmp/* && rmdir tmp || exit

							echo -e "`date +"%d %b %Y %T"` - Concluído com sucesso!" | tee ${WORK_DIR}/$(basename $0 | cut -d . -f 1).log

						fi

					fi

				fi

			fi

		else

			echo "Não há arquivos de backup em \"${ORIGEM_BKP}/$SELECTED_DB\"."

		fi

	}

	WORK_DIR=`pwd`
	cd $ORIGEM_BKP && BKP_DB=`ls -d *` || exit

	if [ -n "$BKP_DB" ]
	then

		SELECTED_DB=$(whiptail --backtitle "Firebird Backup Management Tool" --title "Selecionar Arquivo" --menu "\nSelecione o arquivo correspondente ao Banco de Dados..." --ok-button "Selecionar" --cancel-button "Cancelar" 12 59 3 `for DB in ${BKP_DB[@]}; do echo $DB "-"; done` 3>&1 1>&2 2>&3)

		if [ $? -eq 0 ]
		then

			cd $SELECTED_DB

			SELECTED_OPT=$(whiptail --backtitle "Firebird Backup Management Tool" --title "Selecionar Backup" --menu "\nPor favor, selecione uma das opções do menu a seguir..." --ok-button "Selecionar" --cancel-button "Cancelar" 12 65 3 \
			"1" "Restaurar o último backup criado (o mais recente)" \
			"2" "Selecionar e restaurar um backup criado hoje..."\
			"3" "Selecionar e restaurar um backup criado anteriormente" 3>&1 1>&2 2>&3)

			if [ $? -eq 0 ]
			then

				BASENAME=`basename $SCRIPT_BKP | cut -d . -f 1`
				source ${WORK_DIR}/.${BASENAME}/${SELECTED_DB}/tar.db && DATA=`date +%d/%m/%Y -d ${BKP_DATE}` || exit

				if [ $SELECTED_OPT -eq 1 ]
				then

					# Restaurar o último backup criado (o mais recente)
					test -e ${WORK_DIR}/.${BASENAME}/${SELECTED_DB}/tar.lst || exit

					HORA=`cat ${WORK_DIR}/.${BASENAME}/${SELECTED_DB}/tar.lst | tail -n 1 | cut -d - -f 3 | sed -r 's/(.{8})(.{2})(.{2}).*/\2/'`
					MINUTOS=`cat ${WORK_DIR}/.${BASENAME}/${SELECTED_DB}/tar.lst | tail -n 1 | cut -d - -f 3 | sed -r 's/(.{8})(.{2})(.{2}).*/\3/'`

					echo -e "`date +"%d %b %Y %T"` - Verificar e confirmar o backup a ser restaurado...\n"

					echo -e "\tData/Hora do Backup:\t$DATA ${HORA}:${MINUTOS}"
					echo -e "\tDatabase Original:\t${DESTINO_BKP}/${SELECTED_DB}.fdb"
					echo -e "\tRestaurar para:\t\t${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb\n"

					echo -ne "Deseja continuar?! (Case-sensitive) [y|N]: "
					read OPT

					if [ -n "$OPT" ] && [ "$OPT" == "y" ]
					then

						echo -e "\n`date +"%d %b %Y %T"` - Restaurando o backup selecionado p/ \"${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb\"..." | tee ${WORK_DIR}/$(basename $0 | cut -d . -f 1).log
						nbackup -R ${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb $(<${WORK_DIR}/.${BASENAME}/${SELECTED_DB}/tar.lst) || exit

						echo -e "`date +"%d %b %Y %T"` - Atribuindo permissões ao \"${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb\"..."
						chgrp firebird ${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb || exit
						chmod g+w ${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb || exit

						echo -e "`date +"%d %b %Y %T"` - Concluído com sucesso!" | tee ${WORK_DIR}/$(basename $0 | cut -d . -f 1).log

					fi

				elif [ $SELECTED_OPT -eq 2 ]
				then

					# Selecionar e restaurar um backup criado hoje...
					test -e ${WORK_DIR}/.${BASENAME}/${SELECTED_DB}/tar.lst && FILES=`cat ${WORK_DIR}/.${BASENAME}/${SELECTED_DB}/tar.lst | grep ^"${SELECTED_DB}-incr" | sort -r` || exit

					ARQUIVO_NBK=$(whiptail --backtitle "Firebird Backup Management Tool" --title "Selecionar Arquivo" --menu "\nSelecione o arquivo correspondente a \"data/hora\" do backup..." --ok-button "Selecionar" --cancel-button "Cancelar" 14 65 5 `for FILE in ${FILES[@]}; do echo $FILE "-"; done` 3>&1 1>&2 2>&3)

					if [ $? -eq 0 ]
					then

						HORA=`echo "$ARQUIVO_NBK" | cut -d - -f 3 | sed -r 's/(.{4})(.{2})(.{2})(.{2})(.{2}).*/\4/'`
						MINUTOS=`echo "$ARQUIVO_NBK" | cut -d - -f 3 | sed -r 's/(.{4})(.{2})(.{2})(.{2})(.{2}).*/\5/'`

						echo -e "`date +"%d %b %Y %T"` - Verificar e confirmar o backup a ser restaurado...\n"

						echo -e "\tData/Hora do Backup:\t$DATA ${HORA}:${MINUTOS}"
						echo -e "\tDatabase Original:\t${DESTINO_BKP}/${SELECTED_DB}.fdb"
						echo -e "\tRestaurar para:\t\t${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb\n"

						echo -ne "Deseja continuar?! (Case-sensitive) [y|N]: "
						read OPT

						if [ -n "$OPT" ] && [ "$OPT" == "y" ]
						then

							echo -e "\n`date +"%d %b %Y %T"` - Gerando lista de arquivos do \"nbackup\"..."
							test -e ./nbackup.lst && rm ./nbackup.lst

							while read file
							do

								echo $file >>./nbackup.lst || exit
								test "`basename $file`" = "$ARQUIVO_NBK" && break

							done < ${WORK_DIR}/.${BASENAME}/${SELECTED_DB}/tar.lst

							echo -e "`date +"%d %b %Y %T"` - Restaurando o backup selecionado p/ \"${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb\"..." | tee ${WORK_DIR}/$(basename $0 | cut -d . -f 1).log
							nbackup -R ${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb $(<./nbackup.lst) || exit
							rm ./tmp/nbackup.lst

							echo -e "`date +"%d %b %Y %T"` - Atribuindo permissões ao \"${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb\"..."
							chgrp firebird ${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb || exit
							chmod g+w ${DESTINO_BKP}/bkp-${SELECTED_DB}-`date +%Y%m%d -d ${BKP_DATE}`${HORA}${MINUTOS}.fdb || exit

							echo -e "`date +"%d %b %Y %T"` - Concluído com sucesso!" | tee ${WORK_DIR}/$(basename $0 | cut -d . -f 1).log

						fi

					fi

				else

					bkp_antigo

				fi

			fi

		fi

	else

		echo "Não há arquivos de backup em \"$ORIGEM_BKP\"."

	fi
